import Foundation

/// Snapshot of what the active media source is currently doing.
///
/// `position` is the playback position in seconds as it was at `updatedAt`.
/// While `isPlaying` is true the UI extrapolates with `position(at:)`.
struct NowPlaying: Equatable, Sendable {
    /// Which MusicDesk source produced this snapshot (nil = none active).
    var source: MediaSourceKind?
    /// Bundle id of the app that is actually playing (e.g. com.apple.Safari
    /// for YouTube via the system source). Used for the optional source icon.
    var appBundleIdentifier: String?
    /// Human readable name of that app, if known.
    var appName: String?
    var isPlaying: Bool
    var title: String?
    /// Artist, or channel/website for browser media. nil/empty = none.
    var artist: String?
    var position: Double      // seconds, as reported at `updatedAt`
    var duration: Double      // seconds, 0 = unknown (e.g. livestream)
    var updatedAt: Date
    /// 1 = normal speed. Used for extrapolation while playing.
    var playbackRate: Double = 1

    /// Nothing playing, 0/0.
    static let idle = NowPlaying(
        source: nil, appBundleIdentifier: nil, appName: nil,
        isPlaying: false, title: nil, artist: nil,
        position: 0, duration: 0, updatedAt: Date()
    )

    /// Sample used by the live preview in the settings window.
    static let sample = NowPlaying(
        source: .appleMusic, appBundleIdentifier: "com.apple.Music", appName: "Musik",
        isPlaying: true, title: "Blinding Lights", artist: "The Weeknd",
        position: 74, duration: 200, updatedAt: Date()
    )

    /// True when there is a non-empty title.
    var hasTrack: Bool { !Self.clean(title).isEmpty }

    /// True when a usable, finite duration is known (seeking possible).
    var hasDuration: Bool { duration.isFinite && duration > 0 }

    /// Position extrapolated to `date` while playing, clamped to 0...duration.
    func position(at date: Date) -> Double {
        var value = position
        if isPlaying {
            let rate = (playbackRate.isFinite && playbackRate > 0) ? playbackRate : 1
            value += date.timeIntervalSince(updatedAt) * rate
        }
        if !value.isFinite || value < 0 { value = 0 }
        if hasDuration, value > duration { value = duration }
        return value
    }

    /// 0...1, 0 when no duration is known.
    func progress(at date: Date) -> Double {
        guard hasDuration else { return 0 }
        let fraction = position(at: date) / duration
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// Title, or "Nichts läuft" when there is no track.
    var displayTitle: String { hasTrack ? Self.clean(title) : "Nichts läuft" }

    /// Artist/channel, nil when empty or when there is no track
    /// (so the UI never renders a dangling comma).
    var displayArtist: String? {
        guard hasTrack else { return nil }
        let a = Self.clean(artist)
        return a.isEmpty ? nil : a
    }

    /// "Titel, Künstler" / "Titel" / "Nichts läuft".
    var displayText: String {
        if let a = displayArtist { return "\(displayTitle), \(a)" }
        return displayTitle
    }

    private static func clean(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
