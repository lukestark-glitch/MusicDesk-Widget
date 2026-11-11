import AppKit
import Foundation
import os

/// AppleScript snippets for one scriptable player app.
///
/// `fetch` must return the list `{state, name, artist, position, duration}`
/// with state "playing"/"paused"/"stopped" (or "notrunning"), position and
/// duration in SECONDS. Do not wrap `player state` in `try`, so permission
/// errors (-1743) propagate.
struct PlayerScripts {
    let fetch: String
    let playPause: String
    let nextTrack: String
    let previousTrack: String
    /// Absolute seek in seconds.
    let seek: (Double) -> String
}

/// Static description of a scriptable player (Apple Music, Spotify).
struct ScriptablePlayerConfig {
    let kind: MediaSourceKind
    let bundleIdentifier: String
    let appName: String
    /// Distributed notification the app posts on every playback change.
    let notificationName: String
    let scripts: PlayerScripts
}

/// Shared implementation for players controlled via AppleScript
/// (port of the 1.0 `MusicController`).
///
/// - Never launches the player: every script is guarded by an
///   NSRunningApplication check (and an `is running` check inside the script).
/// - All AppleScript work runs on one serial background queue (`AppleScriptRunner.shared`).
/// - Updates come from the app's distributed notification (immediate), a 1 s
///   polling timer (only while the app runs) and NSWorkspace launch/terminate observers.
/// - Commands update the state optimistically and refetch right afterwards;
///   after a seek, disagreeing polls are ignored for a short grace period.
@MainActor
class ScriptablePlayerSource: MediaSource {
    let kind: MediaSourceKind

    private(set) var state: NowPlaying = .idle {
        didSet {
            if state != oldValue {
                onChange?(state)
            }
        }
    }

    var onChange: ((NowPlaying) -> Void)?

    private let config: ScriptablePlayerConfig
    private let runner = AppleScriptRunner.shared
    private let logger: Logger

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

    /// Shortly after the app terminated, don't send any AppleEvents.
    private var suppressScriptsUntil: Date = .distantPast

    /// Error bookkeeping (avoid log spam).
    private var lastErrorCode: Int?
    private var permissionDenied = false
    private var lastDeniedAttempt: Date = .distantPast

    private var refetchWorkItem: DispatchWorkItem?

    private static let seekGracePeriod: TimeInterval = 1.5
    private static let commandRefetchDelay: TimeInterval = 0.15

    init(config: ScriptablePlayerConfig) {
        self.config = config
        self.kind = config.kind
        self.logger = Logger(subsystem: "com.musicdesk.widget", category: config.kind.rawValue)
    }

    // MARK: - Public helpers

    var bundleIdentifier: String { config.bundleIdentifier }

    /// True when the player app runs and may be scripted right now.
    var isAppRunning: Bool { canSendScripts() }

    // MARK: - Lifecycle

    /// Begins observing (distributed notification, launch/terminate, polling while running).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Results of fetches started before a previous stop() are stale.
        localGeneration += 1

        let kind = config.kind
        let bundleID = config.bundleIdentifier

        let distributed: NotificationCenter = DistributedNotificationCenter.default()
        let infoToken = distributed.addObserver(
            forName: Notification.Name(config.notificationName),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let info = ScriptedPlayerInfo(userInfo: notification.userInfo, kind: kind)
            MainActor.assumeIsolated {
                self?.handlePlayerInfo(info)
            }
        }
        observers.append((center: distributed, token: infoToken))

        let workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
        let launchToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let launchedID = ScriptablePlayerSource.runningAppBundleIdentifier(from: notification)
            MainActor.assumeIsolated {
                guard launchedID == bundleID else { return }
                self?.handleAppLaunched()
            }
        }
        observers.append((center: workspaceCenter, token: launchToken))

        let terminateToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminatedID = ScriptablePlayerSource.runningAppBundleIdentifier(from: notification)
            MainActor.assumeIsolated {
                guard terminatedID == bundleID else { return }
                self?.handleAppTerminated()
            }
        }
        observers.append((center: workspaceCenter, token: terminateToken))

        logger.info("\(self.config.appName, privacy: .public) source started")

        if AppleScriptRunner.isRunning(bundleIdentifier: bundleID) {
            startPolling()
            requestFetch()
        } else {
            applyNotRunning()
        }
    }

    /// Stops observing and polling. The state is reset to `.idle`.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        stopPolling()
        refetchWorkItem?.cancel()
        refetchWorkItem = nil
        fetchPending = false
        for entry in observers {
            entry.center.removeObserver(entry.token)
        }
        observers.removeAll()
        logger.info("\(self.config.appName, privacy: .public) source stopped")
        applyNotRunning()
    }

    // MARK: - Commands

    func playPause() {
        guard isStarted else { return }
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
        runCommand(config.scripts.playPause, cacheKey: "playpause")
    }

    func nextTrack() {
        guard isStarted else { return }
        guard canSendScripts() else { applyNotRunning(); return }
        localGeneration += 1
        runCommand(config.scripts.nextTrack, cacheKey: "next")
    }

    func previousTrack() {
        guard isStarted else { return }
        guard canSendScripts() else { applyNotRunning(); return }
        localGeneration += 1
        runCommand(config.scripts.previousTrack, cacheKey: "previous")
    }

    /// Optimistic local update of `state`, then AppleScript "set player position".
    func seek(to seconds: Double) {
        guard isStarted else { return }
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
        seekGraceUntil = Date().addingTimeInterval(ScriptablePlayerSource.seekGracePeriod)
        state = updated

        // Not cached: the value is part of the source.
        runCommand(config.scripts.seek(target), cacheKey: nil)
    }

    // MARK: - Polling / fetching

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        guard isStarted else { return }
        if permissionDenied, Date().timeIntervalSince(lastDeniedAttempt) < 5 {
            return
        }
        requestFetch()
    }

    private func canSendScripts() -> Bool {
        Date() >= suppressScriptsUntil
            && AppleScriptRunner.isRunning(bundleIdentifier: config.bundleIdentifier)
    }

    private func requestFetch() {
        guard isStarted else { return }
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
            bundleIdentifier: config.bundleIdentifier,
            source: config.scripts.fetch,
            cacheKey: "fetch",
            parse: { descriptor in ScriptedFetchResult(descriptor: descriptor) },
            completion: { [weak self] outcome in
                self?.handleFetch(outcome, generation: generation)
            }
        )
    }

    private func handleFetch(_ outcome: AppleScriptOutcome<ScriptedFetchResult>, generation: Int) {
        fetchInFlight = false
        guard isStarted else {
            fetchPending = false
            return
        }

        switch outcome {
        case .appNotRunning:
            applyNotRunning()
        case let .failure(code, message):
            handleScriptError(code: code, message: message)
        case let .success(result):
            clearErrorState()
            if !result.appRunning {
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

    private func apply(_ result: ScriptedFetchResult) {
        let now = result.timestamp
        var fetched = NowPlaying(
            source: config.kind,
            appBundleIdentifier: config.bundleIdentifier,
            appName: config.appName,
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
        let sameTrack = current.source == config.kind
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
            bundleIdentifier: config.bundleIdentifier,
            source: source,
            cacheKey: cacheKey,
            parse: { _ in true },
            completion: { [weak self] outcome in
                guard let self, self.isStarted else { return }
                switch outcome {
                case .success:
                    self.clearErrorState()
                case .appNotRunning:
                    self.applyNotRunning()
                case let .failure(code, message):
                    self.handleScriptError(code: code, message: message)
                }
                self.scheduleRefetch(after: ScriptablePlayerSource.commandRefetchDelay)
            }
        )
    }

    private func scheduleRefetch(after delay: TimeInterval) {
        guard isStarted else { return }
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

    private func handlePlayerInfo(_ info: ScriptedPlayerInfo) {
        guard isStarted else { return }
        guard canSendScripts() else {
            applyNotRunning()
            return
        }

        let now = Date()
        var updated = state
        updated.source = config.kind
        updated.appBundleIdentifier = config.bundleIdentifier
        updated.appName = config.appName
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
            if let duration = info.durationSeconds, duration.isFinite, duration > 0 {
                updated.duration = duration
            }
            // Spotify reports the position directly (not during a seek grace period,
            // where the optimistic value wins until a fetch confirms it).
            if let position = info.positionSeconds, position.isFinite, position >= 0,
               Date() >= seekGraceUntil {
                updated.position = updated.duration > 0 ? min(position, updated.duration) : position
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

    private func handleAppLaunched() {
        guard isStarted else { return }
        logger.info("\(self.config.appName, privacy: .public) launched")
        suppressScriptsUntil = .distantPast
        startPolling()
        // The app needs a moment before it answers AppleEvents.
        scheduleRefetch(after: 1.0)
        // Let the manager re-evaluate the source selection.
        onChange?(state)
    }

    private func handleAppTerminated() {
        guard isStarted else { return }
        logger.info("\(self.config.appName, privacy: .public) terminated")
        // runningApplications can lag a little behind the notification;
        // don't risk an AppleEvent that would relaunch the app.
        suppressScriptsUntil = Date().addingTimeInterval(2.0)
        stopPolling()
        refetchWorkItem?.cancel()
        refetchWorkItem = nil
        runner.resetCache(bundleIdentifier: config.bundleIdentifier)
        clearErrorState()
        if state != .idle {
            applyNotRunning()       // publishes via didSet
        } else {
            onChange?(state)        // still let the manager re-evaluate
        }
    }

    // MARK: - State helpers

    private func applyNotRunning() {
        if state != .idle {
            state = .idle
        }
    }

    private func clearErrorState() {
        if permissionDenied {
            logger.info("AppleEvent access to \(self.config.appName, privacy: .public) is now permitted")
        }
        permissionDenied = false
        lastErrorCode = nil
    }

    private func handleScriptError(code: Int, message: String) {
        switch code {
        case -1743, -1744:
            // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
            if !permissionDenied {
                logger.error("Not permitted to control \(self.config.appName, privacy: .public) (\(code, privacy: .public)). Allow MusicDesk in System Settings > Privacy & Security > Automation.")
            }
            permissionDenied = true
            lastDeniedAttempt = Date()
            let denied = NowPlaying(
                source: config.kind,
                appBundleIdentifier: config.bundleIdentifier,
                appName: config.appName,
                isPlaying: false,
                title: nil,
                artist: nil,
                position: 0,
                duration: 0,
                updatedAt: NowPlaying.idle.updatedAt
            )
            if state != denied {
                state = denied
            }
        case -600, -609, -903:
            // App not running / connection invalid / no such app: the app went away.
            runner.resetCache(bundleIdentifier: config.bundleIdentifier)
            if lastErrorCode != code {
                logger.debug("\(self.config.appName, privacy: .public) not reachable (\(code, privacy: .public)): \(message, privacy: .public)")
            }
            applyNotRunning()
        default:
            if lastErrorCode != code {
                logger.error("AppleScript error \(code, privacy: .public): \(message, privacy: .public)")
            }
        }
        lastErrorCode = code
    }

    nonisolated private static func runningAppBundleIdentifier(from notification: Notification) -> String? {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier
    }
}

// MARK: - Helper types

/// Sendable extract of a player's distributed notification userInfo.
///
/// Apple Music (`com.apple.Music.playerInfo`): "Player State", "Name",
/// "Artist", "Total Time" (ms).
/// Spotify (`com.spotify.client.PlaybackStateChanged`): "Player State",
/// "Name", "Artist", "Duration" (ms), "Playback Position" (s).
private struct ScriptedPlayerInfo: Sendable {
    var playerState: String?
    var name: String?
    var artist: String?
    var durationSeconds: Double?
    var positionSeconds: Double?

    init(userInfo: [AnyHashable: Any]?, kind: MediaSourceKind) {
        playerState = userInfo?["Player State"] as? String
        name = userInfo?["Name"] as? String
        artist = userInfo?["Artist"] as? String
        durationSeconds = nil
        positionSeconds = nil
        switch kind {
        case .appleMusic:
            if let ms = Self.number(userInfo?["Total Time"]) {
                durationSeconds = ms / 1000.0
            }
        case .spotify:
            if let ms = Self.number(userInfo?["Duration"]) {
                durationSeconds = ms / 1000.0
            }
            positionSeconds = Self.number(userInfo?["Playback Position"])
        case .system:
            break
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            let d = number.doubleValue
            return d.isFinite ? d : nil
        }
        return nil
    }
}

/// Parsed result of a fetch script (an AppleEvent list {state, name, artist, pos, dur}).
private struct ScriptedFetchResult: Sendable {
    var appRunning: Bool
    var playerState: String   // "playing" / "paused" / "stopped"
    var title: String
    var artist: String
    var position: Double
    var duration: Double
    var timestamp: Date

    init(descriptor: NSAppleEventDescriptor) {
        timestamp = Date()
        let state = ScriptedFetchResult.string(descriptor, 1)
        if descriptor.numberOfItems < 5 || state.isEmpty {
            appRunning = true
            playerState = "stopped"
            title = ""
            artist = ""
            position = 0
            duration = 0
            return
        }
        appRunning = state != "notrunning"
        playerState = state
        title = ScriptedFetchResult.string(descriptor, 2)
        artist = ScriptedFetchResult.string(descriptor, 3)
        position = ScriptedFetchResult.number(descriptor, 4)
        duration = ScriptedFetchResult.number(descriptor, 5)
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
