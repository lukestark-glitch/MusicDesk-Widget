import Foundation

/// Snapshot of what Apple Music is currently doing.
///
/// `position` is the playback position in seconds as it was at `updatedAt`.
/// While `isPlaying` is true the UI extrapolates with `position(at:)`.
struct PlaybackState: Equatable, Sendable {
    var isMusicRunning: Bool
    var isPlaying: Bool
    var title: String?
    var artist: String?
    var position: Double      // seconds, as reported at `updatedAt`
    var duration: Double      // seconds, 0 if unknown
    var updatedAt: Date

    /// Music not running, nothing playing, 0/0.
    static let idle = PlaybackState(
        isMusicRunning: false,
        isPlaying: false,
        title: nil,
        artist: nil,
        position: 0,
        duration: 0,
        updatedAt: Date()
    )

    /// True when there is a non-empty title.
    var hasTrack: Bool {
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Position extrapolated to `date` while playing, clamped to 0...duration.
    func position(at date: Date) -> Double {
        var value = position
        if isPlaying {
            value += date.timeIntervalSince(updatedAt)
        }
        if !value.isFinite { value = 0 }
        if value < 0 { value = 0 }
        if duration > 0, value > duration { value = duration }
        return value
    }

    /// 0...1, 0 when duration <= 0.
    func progress(at date: Date) -> Double {
        guard duration > 0, duration.isFinite else { return 0 }
        let fraction = position(at: date) / duration
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }

    /// "Titel, Künstler" / just title / "Nichts läuft" when !hasTrack.
    var displayText: String {
        guard hasTrack, let title else { return "Nichts läuft" }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanArtist.isEmpty {
            return cleanTitle
        }
        return "\(cleanTitle), \(cleanArtist)"
    }
}
