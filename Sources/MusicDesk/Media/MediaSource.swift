import Foundation

/// The concrete backends MusicDesk can read from.
enum MediaSourceKind: String, CaseIterable, Sendable {
    case appleMusic
    case spotify
    /// System-wide Now Playing (any app, e.g. YouTube in Safari/Chrome),
    /// via the bundled mediaremote-adapter.
    case system

    /// German display name.
    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .system: return "Alles auf dem Mac"
        }
    }

    /// Bundle id of the player app (nil for the system source).
    var bundleIdentifier: String? {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .system: return nil
        }
    }

    /// Fallback SF Symbol when no app icon is available.
    var symbolName: String {
        switch self {
        case .appleMusic: return "music.note"
        case .spotify: return "music.note.list"
        case .system: return "play.rectangle.on.rectangle"
        }
    }
}

/// User setting "Quelle". Raw values are stored in UserDefaults.
enum SourcePreference: String, CaseIterable, Sendable {
    /// System source if available, otherwise the app that is playing
    /// (Apple Music before Spotify).
    case automatic
    case appleMusic
    case spotify
    case system

    var displayName: String {
        switch self {
        case .automatic: return "Automatisch"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .system: return "Alles auf dem Mac"
        }
    }
}

/// Availability of the system-wide source (result of the adapter `test`).
enum SystemSourceAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable(reason: String)
}

/// One media backend. The UI never talks to a source directly – only to
/// `MediaManager`, which owns all sources and forwards the active one's state.
///
/// Implementations: never launch a player app (check NSRunningApplication
/// before every AppleScript call), never block the main thread.
@MainActor
protocol MediaSource: AnyObject {
    var kind: MediaSourceKind { get }
    /// Latest snapshot. Must have `source == kind` when it describes media.
    var state: NowPlaying { get }
    /// Called on the main actor whenever `state` changes.
    var onChange: ((NowPlaying) -> Void)? { get set }

    /// Begin observing (notifications, polling, helper process …). Idempotent.
    func start()
    /// Stop observing and release resources (timers, child processes). Idempotent.
    func stop()

    func playPause()
    func nextTrack()
    func previousTrack()
    /// Seek to an absolute position in seconds. No-op without a duration.
    func seek(to seconds: Double)
}
