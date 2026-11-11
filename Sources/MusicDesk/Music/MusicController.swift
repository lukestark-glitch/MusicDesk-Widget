import AppKit
import Combine
import Foundation
import os

/// Connection layer to Apple Music.
///
/// - Never launches Music: every script is guarded by an NSRunningApplication
///   check (and an `application "Music" is running` check inside the script).
/// - All AppleScript work runs on one serial background queue (`AppleScriptRunner`).
/// - Updates come from the `com.apple.Music.playerInfo` distributed notification
///   (immediate), a 1 s polling timer and NSWorkspace launch/terminate observers.
@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var state: PlaybackState = .idle

    private let runner = AppleScriptRunner()
    private let logger = Logger(subsystem: "com.musicdesk.widget", category: "Music")

    private var isStarted = false
    private var pollTimer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// Fetch coalescing.
    private var fetchInFlight = false
    private var fetchPending = false

    /// Incremented on every local (optimistic) change. A fetch that was started
    /// before the latest local change is stale and gets discarded.
    private var localGeneration = 0

    /// After a seek, polls that disagree with the optimistic position are ignored until then.
    private var seekGraceUntil: Date = .distantPast

    /// Shortly after Music terminated, don't send any AppleEvents.
    private var suppressScriptsUntil: Date = .distantPast

    /// Error bookkeeping (avoid log spam).
    private var lastErrorCode: Int?
    private var permissionDenied = false
    private var lastDeniedAttempt: Date = .distantPast

    private var refetchWorkItem: DispatchWorkItem?

    private static let musicBundleID = AppleScriptRunner.musicBundleIdentifier
    private static let playerInfoNotification = Notification.Name("com.apple.Music.playerInfo")
    private static let seekGracePeriod: TimeInterval = 1.5
    private static let commandRefetchDelay: TimeInterval = 0.15

    init() {}

    // MARK: - Lifecycle

    /// Begins observing Music (distributed notification, 1 s timer, launch/terminate).
    func start() {
        guard !isStarted else { return }
        isStarted = true

        let distributed: NotificationCenter = DistributedNotificationCenter.default()
        let playerInfoToken = distributed.addObserver(
            forName: Self.playerInfoNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = PlayerInfoSnapshot(userInfo: notification.userInfo)
            MainActor.assumeIsolated {
                self?.handlePlayerInfo(info)
            }
        }
        observers.append((center: distributed, token: playerInfoToken))

        let workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
        let launchToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = Self.bundleIdentifier(from: notification)
            MainActor.assumeIsolated {
                guard bundleID == Self.musicBundleID else { return }
                self?.handleMusicLaunched()
            }
        }
        observers.append((center: workspaceCenter, token: launchToken))

        let terminateToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = Self.bundleIdentifier(from: notification)
            MainActor.assumeIsolated {
                guard bundleID == Self.musicBundleID else { return }
                self?.handleMusicTerminated()
            }
        }
        observers.append((center: workspaceCenter, token: terminateToken))

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        logger.info("MusicController started")
        requestFetch()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pollTimer?.invalidate()
        pollTimer = nil
        refetchWorkItem?.cancel()
        refetchWorkItem = nil
        for entry in observers {
            entry.center.removeObserver(entry.token)
        }
        observers.removeAll()
        logger.info("MusicController stopped")
    }

    // MARK: - Commands

    func playPause() {
        guard canSendScripts() else { applyNotRunning(); return }
        if state.hasTrack {
            let now = Date()
            var updated = state
            updated.position = state.position(at: now)
            updated.updatedAt = now
            updated.isPlaying.toggle()
            localGeneration += 1
            state = updated
        }
        runCommand(Scripts.playPause, cacheKey: "playpause")
    }

    func nextTrack() {
        guard canSendScripts() else { applyNotRunning(); return }
        localGeneration += 1
        runCommand(Scripts.nextTrack, cacheKey: "next")
    }

    func previousTrack() {
        guard canSendScripts() else { applyNotRunning(); return }
        localGeneration += 1
        runCommand(Scripts.previousTrack, cacheKey: "previous")
    }

    /// Optimistic local update of `state`, then AppleScript "set player position".
    func seek(to seconds: Double) {
        guard canSendScripts() else { applyNotRunning(); return }
        guard state.hasTrack, seconds.isFinite else { return }

        var target = max(0, seconds)
        if state.duration > 0 {
            target = min(target, state.duration)
        }

        var updated = state
        updated.position = target
        updated.updatedAt = Date()
        localGeneration += 1
        seekGraceUntil = Date().addingTimeInterval(Self.seekGracePeriod)
        state = updated

        // Not cached: the value is part of the source. String(format:) uses the
        // POSIX locale, so the decimal separator is always ".".
        let source = Scripts.seek(to: target)
        runCommand(source, cacheKey: nil)
    }

    // MARK: - Polling / fetching

    private func poll() {
        if permissionDenied, Date().timeIntervalSince(lastDeniedAttempt) < 5 {
            return
        }
        requestFetch()
    }

    private func canSendScripts() -> Bool {
        Date() >= suppressScriptsUntil && AppleScriptRunner.isMusicRunning()
    }

    private func requestFetch() {
        guard canSendScripts() else {
            applyNotRunning()
            return
        }
        if fetchInFlight {
            fetchPending = true
            return
        }
        fetchInFlight = true
        if permissionDenied { lastDeniedAttempt = Date() }
        let generation = localGeneration

        runner.run(
            source: Scripts.fetch,
            cacheKey: "fetch",
            parse: { descriptor in FetchResult(descriptor: descriptor) },
            completion: { [weak self] outcome in
                self?.handleFetch(outcome, generation: generation)
            }
        )
    }

    private func handleFetch(_ outcome: AppleScriptOutcome<FetchResult>, generation: Int) {
        fetchInFlight = false

        switch outcome {
        case .musicNotRunning:
            applyNotRunning()
        case let .failure(code, message):
            handleScriptError(code: code, message: message)
        case let .success(result):
            clearErrorState()
            if !result.musicRunning {
                applyNotRunning()
            } else if generation != localGeneration {
                // Started before a local optimistic change: stale, fetch again.
                fetchPending = true
            } else {
                apply(result)
            }
        }

        if fetchPending {
            fetchPending = false
            requestFetch()
        }
    }

    private func apply(_ result: FetchResult) {
        let now = result.timestamp
        var fetched = PlaybackState(
            isMusicRunning: true,
            isPlaying: result.playerState == "playing",
            title: result.title.isEmpty ? nil : result.title,
            artist: result.artist.isEmpty ? nil : result.artist,
            position: max(0, result.position),
            duration: max(0, result.duration),
            updatedAt: now
        )
        if result.playerState == "stopped" && !fetched.hasTrack {
            fetched.position = 0
            fetched.duration = 0
        }

        let current = state
        let sameTrack = current.isMusicRunning
            && current.title == fetched.title
            && current.artist == fetched.artist
            && abs(current.duration - fetched.duration) < 0.5
        let expected = current.position(at: now)

        // Seek grace: ignore positions that disagree with the optimistic seek.
        if Date() < seekGraceUntil {
            if sameTrack && abs(expected - fetched.position) > 1.0 {
                fetched.position = expected
            } else {
                seekGraceUntil = .distantPast   // confirmed (or track changed)
            }
        }

        // Keep the existing time base when the fetched value agrees, so the
        // knob doesn't jitter and identical states aren't republished.
        if sameTrack && current.isPlaying == fetched.isPlaying {
            let tolerance = fetched.isPlaying ? 0.35 : 0.01
            if abs(expected - fetched.position) <= tolerance {
                fetched.position = current.position
                fetched.updatedAt = current.updatedAt
            }
        }

        if fetched != state {
            state = fetched
        }
    }

    // MARK: - Commands helper

    private func runCommand(_ source: String, cacheKey: String?) {
        runner.run(
            source: source,
            cacheKey: cacheKey,
            parse: { _ in true },
            completion: { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .success:
                    self.clearErrorState()
                case .musicNotRunning:
                    self.applyNotRunning()
                case let .failure(code, message):
                    self.handleScriptError(code: code, message: message)
                }
                self.scheduleRefetch(after: Self.commandRefetchDelay)
            }
        )
    }

    private func scheduleRefetch(after delay: TimeInterval) {
        refetchWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.refetchWorkItem = nil
                self?.requestFetch()
            }
        }
        refetchWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Notifications

    private func handlePlayerInfo(_ info: PlayerInfoSnapshot) {
        guard AppleScriptRunner.isMusicRunning() else {
            applyNotRunning()
            return
        }

        let now = Date()
        var updated = state
        updated.isMusicRunning = true
        updated.position = state.position(at: now)
        updated.updatedAt = now

        let playerState = info.playerState?.lowercased()
        switch playerState {
        case "playing"?:
            updated.isPlaying = true
        case "paused"?:
            updated.isPlaying = false
        case "stopped"?:
            updated.isPlaying = false
        default:
            break
        }

        if let name = info.name, !name.isEmpty {
            if name != updated.title || (info.artist != nil && info.artist != updated.artist) {
                updated.position = 0   // track changed
            }
            updated.title = name
            if let artist = info.artist {
                updated.artist = artist.isEmpty ? nil : artist
            }
            if let totalMs = info.totalTimeMs, totalMs.isFinite, totalMs > 0 {
                updated.duration = totalMs / 1000.0
            }
        } else if playerState == "stopped" {
            updated.title = nil
            updated.artist = nil
            updated.position = 0
            updated.duration = 0
        }

        // Notification is newer than any fetch currently in flight.
        localGeneration += 1
        if updated != state {
            state = updated
        }
        // Confirm details (position etc.) with a real fetch.
        scheduleRefetch(after: 0.05)
    }

    private func handleMusicLaunched() {
        logger.info("Apple Music launched")
        suppressScriptsUntil = .distantPast
        // Music needs a moment before it answers AppleEvents.
        scheduleRefetch(after: 1.0)
    }

    private func handleMusicTerminated() {
        logger.info("Apple Music terminated")
        // runningApplications can lag a little behind the notification;
        // don't risk an AppleEvent that would relaunch Music.
        suppressScriptsUntil = Date().addingTimeInterval(2.0)
        refetchWorkItem?.cancel()
        refetchWorkItem = nil
        runner.resetCache()
        clearErrorState()
        applyNotRunning()
    }

    // MARK: - State helpers

    private func applyNotRunning() {
        if state != .idle {
            state = .idle
        }
    }

    private func clearErrorState() {
        if permissionDenied {
            logger.info("AppleEvent access to Music is now permitted")
        }
        permissionDenied = false
        lastErrorCode = nil
    }

    private func handleScriptError(code: Int, message: String) {
        switch code {
        case -1743, -1744:
            // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
            if !permissionDenied {
                logger.error("Not permitted to control Apple Music (\(code, privacy: .public)). Allow MusicDesk in System Settings > Privacy & Security > Automation.")
            }
            permissionDenied = true
            lastDeniedAttempt = Date()
            let denied = PlaybackState(
                isMusicRunning: true,
                isPlaying: false,
                title: nil,
                artist: nil,
                position: 0,
                duration: 0,
                updatedAt: PlaybackState.idle.updatedAt
            )
            if state != denied {
                state = denied
            }
        case -600, -609, -903:
            // App not running / connection invalid / no such app: Music went away.
            runner.resetCache()
            if lastErrorCode != code {
                logger.debug("Music not reachable (\(code, privacy: .public)): \(message, privacy: .public)")
            }
            applyNotRunning()
        default:
            if lastErrorCode != code {
                logger.error("AppleScript error \(code, privacy: .public): \(message, privacy: .public)")
            }
        }
        lastErrorCode = code
    }

    nonisolated private static func bundleIdentifier(from notification: Notification) -> String? {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier
    }
}

// MARK: - Helper types

/// Sendable extract of the `com.apple.Music.playerInfo` userInfo.
private struct PlayerInfoSnapshot: Sendable {
    var playerState: String?
    var name: String?
    var artist: String?
    var totalTimeMs: Double?

    init(userInfo: [AnyHashable: Any]?) {
        playerState = userInfo?["Player State"] as? String
        name = userInfo?["Name"] as? String
        artist = userInfo?["Artist"] as? String
        if let number = userInfo?["Total Time"] as? NSNumber {
            totalTimeMs = number.doubleValue
        } else {
            totalTimeMs = nil
        }
    }
}

/// Parsed result of `Scripts.fetch` (an AppleEvent list {state, name, artist, pos, dur}).
private struct FetchResult: Sendable {
    var musicRunning: Bool
    var playerState: String   // "playing" / "paused" / "stopped"
    var title: String
    var artist: String
    var position: Double
    var duration: Double
    var timestamp: Date

    init(descriptor: NSAppleEventDescriptor) {
        timestamp = Date()
        let state = FetchResult.string(descriptor, 1)
        if descriptor.numberOfItems < 5 || state.isEmpty {
            musicRunning = true
            playerState = "stopped"
            title = ""
            artist = ""
            position = 0
            duration = 0
            return
        }
        musicRunning = state != "notrunning"
        playerState = state
        title = FetchResult.string(descriptor, 2)
        artist = FetchResult.string(descriptor, 3)
        position = FetchResult.number(descriptor, 4)
        duration = FetchResult.number(descriptor, 5)
    }

    private static func string(_ list: NSAppleEventDescriptor, _ index: Int) -> String {
        guard list.numberOfItems >= index, let item = list.atIndex(index) else { return "" }
        return item.stringValue ?? ""
    }

    /// Reads the number directly from the descriptor (no locale dependent text parsing).
    private static func number(_ list: NSAppleEventDescriptor, _ index: Int) -> Double {
        guard list.numberOfItems >= index, let item = list.atIndex(index) else { return 0 }
        let value = item.doubleValue
        return value.isFinite ? value : 0
    }
}

// MARK: - Scripts

private enum Scripts {
    /// One round trip: returns {state, name, artist, position, duration}.
    /// `player state` is NOT wrapped in `try`, so permission errors (-1743) propagate.
    static let fetch = """
    if application "Music" is running then
    \twith timeout of 3 seconds
    \t\ttell application "Music"
    \t\t\tset st to "stopped"
    \t\t\tset nm to ""
    \t\t\tset ar to ""
    \t\t\tset pos to 0.0
    \t\t\tset dur to 0.0
    \t\t\tset ps to player state
    \t\t\tif ps is playing then
    \t\t\t\tset st to "playing"
    \t\t\telse if ps is paused then
    \t\t\t\tset st to "paused"
    \t\t\telse if ps is fast forwarding or ps is rewinding then
    \t\t\t\tset st to "playing"
    \t\t\tend if
    \t\t\ttry
    \t\t\t\tset p to player position
    \t\t\t\tif p is not missing value then set pos to p
    \t\t\tend try
    \t\t\ttry
    \t\t\t\tset t to current track
    \t\t\t\ttry
    \t\t\t\t\tset x to name of t
    \t\t\t\t\tif x is not missing value then set nm to x
    \t\t\t\tend try
    \t\t\t\ttry
    \t\t\t\t\tset x to artist of t
    \t\t\t\t\tif x is not missing value then set ar to x
    \t\t\t\tend try
    \t\t\t\ttry
    \t\t\t\t\tset x to duration of t
    \t\t\t\t\tif x is not missing value then set dur to x
    \t\t\t\tend try
    \t\t\tend try
    \t\t\tif nm is "" and st is not "stopped" then
    \t\t\t\ttry
    \t\t\t\t\tset x to current stream title
    \t\t\t\t\tif x is not missing value then set nm to x
    \t\t\t\tend try
    \t\t\tend if
    \t\t\treturn {st, nm, ar, pos, dur}
    \t\tend tell
    \tend timeout
    else
    \treturn {"notrunning", "", "", 0.0, 0.0}
    end if
    """

    static let playPause = """
    if application "Music" is running then
    \twith timeout of 3 seconds
    \t\ttell application "Music" to playpause
    \tend timeout
    end if
    return true
    """

    static let nextTrack = """
    if application "Music" is running then
    \twith timeout of 3 seconds
    \t\ttell application "Music" to next track
    \tend timeout
    end if
    return true
    """

    static let previousTrack = """
    if application "Music" is running then
    \twith timeout of 3 seconds
    \t\ttell application "Music" to previous track
    \tend timeout
    end if
    return true
    """

    static func seek(to seconds: Double) -> String {
        let value = String(format: "%.3f", seconds)
        return """
        if application "Music" is running then
        \twith timeout of 3 seconds
        \t\ttell application "Music" to set player position to \(value)
        \tend timeout
        end if
        return true
        """
    }
}
