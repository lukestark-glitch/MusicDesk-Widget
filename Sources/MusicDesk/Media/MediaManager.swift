import AppKit
import Combine
import Foundation
import os

/// Owns all media sources, picks the active one and forwards its state.
///
/// Selection (`SourcePreference`):
/// - `.system`/`.automatic`: the system source when the adapter test says
///   `.available`; otherwise automatic selection among the apps.
/// - automatic among apps: Apple Music if playing, else Spotify if playing,
///   else the currently shown app if it is still running (no jumping between
///   two paused players), else Apple Music if running, else Spotify if running,
///   else nothing (`.idle`).
/// - `.appleMusic` / `.spotify`: only that app.
///
/// Only the sources that may be needed run; the system source (perl child
/// process) is stopped whenever it is not used. While the system source's
/// availability is still `.checking` (automatic/system preference), no source
/// runs yet.
@MainActor
final class MediaManager: ObservableObject {
    @Published private(set) var state: NowPlaying = .idle
    @Published private(set) var activeSource: MediaSourceKind? = nil
    @Published private(set) var systemAvailability: SystemSourceAvailability

    private let appleMusic: AppleMusicSource
    private let spotify: SpotifySource
    private let system: SystemNowPlayingSource
    private let logger = Logger(subsystem: "com.musicdesk.widget", category: "MediaManager")

    private var preference: SourcePreference
    private var isStarted = false
    private var didRequestAvailability = false
    private var defaultsObserver: NSObjectProtocol?

    /// Re-entrancy guard: starting/stopping sources may call back into the selection.
    private var isUpdatingSelection = false
    private var selectionNeedsUpdate = false

    init() {
        let system = SystemNowPlayingSource()
        self.appleMusic = AppleMusicSource()
        self.spotify = SpotifySource()
        self.system = system
        self.systemAvailability = system.availability
        self.preference = MediaManager.readPreference()

        appleMusic.onChange = { [weak self] _ in
            self?.updateSelection()
        }
        spotify.onChange = { [weak self] _ in
            self?.updateSelection()
        }
        system.onChange = { [weak self] _ in
            self?.updateSelection()
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preferenceMayHaveChanged()
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        logger.info("MediaManager started (preference: \(self.preference.rawValue, privacy: .public))")

        if !didRequestAvailability {
            didRequestAvailability = true
            system.checkAvailability { [weak self] availability in
                guard let self else { return }
                self.logger.info("System source availability: \(String(describing: availability), privacy: .public)")
                self.systemAvailability = availability
                self.updateSelection()
            }
        }
        updateSelection()
    }

    /// Stops every source (terminates the adapter's perl child process).
    func stop() {
        guard isStarted else { return }
        isStarted = false
        for source in allSources {
            source.stop()
        }
        if activeSource != nil { activeSource = nil }
        if state != .idle { state = .idle }
        logger.info("MediaManager stopped")
    }

    // MARK: - Commands (go to the active source)

    func playPause() {
        activeMediaSource?.playPause()
    }

    func nextTrack() {
        activeMediaSource?.nextTrack()
    }

    func previousTrack() {
        activeMediaSource?.previousTrack()
    }

    func seek(to seconds: Double) {
        activeMediaSource?.seek(to: seconds)
    }

    // MARK: - Selection

    private var allSources: [any MediaSource] { [appleMusic, spotify, system] }

    private var activeMediaSource: (any MediaSource)? {
        guard isStarted, let kind = activeSource else { return nil }
        return source(for: kind)
    }

    private func source(for kind: MediaSourceKind) -> any MediaSource {
        switch kind {
        case .appleMusic: return appleMusic
        case .spotify: return spotify
        case .system: return system
        }
    }

    private func preferenceMayHaveChanged() {
        let newPreference = MediaManager.readPreference()
        guard newPreference != preference else { return }
        logger.info("Source preference changed to \(newPreference.rawValue, privacy: .public)")
        preference = newPreference
        updateSelection()
    }

    private func updateSelection() {
        guard isStarted else { return }
        if isUpdatingSelection {
            selectionNeedsUpdate = true
            return
        }
        isUpdatingSelection = true
        defer { isUpdatingSelection = false }

        var passes = 0
        repeat {
            selectionNeedsUpdate = false
            performSelectionUpdate()
            passes += 1
        } while selectionNeedsUpdate && passes < 4 && isStarted
    }

    private func performSelectionUpdate() {
        // The system source may change its availability at runtime (e.g. the
        // adapter keeps dying); keep the published value in sync.
        let availability = system.availability
        if availability != systemAvailability, availability != .checking {
            systemAvailability = availability
        }

        let useSystem: Bool
        let waitingForSystemCheck: Bool
        switch preference {
        case .automatic, .system:
            useSystem = systemAvailability == .available
            waitingForSystemCheck = systemAvailability == .checking
        case .appleMusic, .spotify:
            useSystem = false
            waitingForSystemCheck = false
        }

        // 1. Run only the sources that may be needed. While the adapter test is
        //    still running (max. 5 s) nothing runs, so Apple Music/Spotify don't
        //    ask for Automation permission when the system source will be used.
        let needed: Set<MediaSourceKind>
        if waitingForSystemCheck {
            needed = []
        } else if useSystem {
            needed = [.system]
        } else {
            switch preference {
            case .appleMusic: needed = [.appleMusic]
            case .spotify: needed = [.spotify]
            case .automatic, .system: needed = [.appleMusic, .spotify]
            }
        }
        for source in allSources where !needed.contains(source.kind) {
            source.stop()
        }
        for source in allSources where needed.contains(source.kind) {
            source.start()
        }

        // 2. Pick the active source.
        let newActive: MediaSourceKind?
        if waitingForSystemCheck {
            newActive = nil
        } else if useSystem {
            newActive = .system
        } else {
            switch preference {
            case .appleMusic:
                newActive = appleMusic.isAppRunning ? .appleMusic : nil
            case .spotify:
                newActive = spotify.isAppRunning ? .spotify : nil
            case .automatic, .system:
                newActive = automaticAppSelection()
            }
        }
        if newActive != activeSource {
            logger.info("Active source: \(newActive?.rawValue ?? "none", privacy: .public)")
            activeSource = newActive
        }

        // 3. Forward the active source's state.
        var newState = NowPlaying.idle
        if let newActive {
            let candidate = source(for: newActive).state
            if candidate.source == newActive {
                newState = candidate
            }
        }
        if newState != state {
            state = newState
        }
    }

    /// Apple Music if playing, else Spotify if playing, else the current app
    /// if still running, else Apple Music if running, else Spotify if running.
    private func automaticAppSelection() -> MediaSourceKind? {
        let musicRunning = appleMusic.isAppRunning
        let spotifyRunning = spotify.isAppRunning
        let musicPlaying = musicRunning && appleMusic.state.source == .appleMusic && appleMusic.state.isPlaying
        let spotifyPlaying = spotifyRunning && spotify.state.source == .spotify && spotify.state.isPlaying

        if musicPlaying { return .appleMusic }
        if spotifyPlaying { return .spotify }
        // Both paused/stopped: keep showing the app the user used last.
        if activeSource == .appleMusic, musicRunning { return .appleMusic }
        if activeSource == .spotify, spotifyRunning { return .spotify }
        if musicRunning { return .appleMusic }
        if spotifyRunning { return .spotify }
        return nil
    }

    private static func readPreference() -> SourcePreference {
        let fallback = SourcePreference(rawValue: SettingsDefault.sourcePreference) ?? .automatic
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.sourcePreference) else {
            return fallback
        }
        return SourcePreference(rawValue: raw) ?? fallback
    }
}
