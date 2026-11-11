import Foundation

/// Spotify (com.spotify.client) via AppleScript. Same behaviour as Apple Music
/// (see `ScriptablePlayerSource`): never launches Spotify, serial script queue,
/// `com.spotify.client.PlaybackStateChanged` notification + 1 s polling while
/// Spotify runs, optimistic commands with immediate refetch, seek grace period.
///
/// Spotify specifics: `player position` is in seconds, `duration` of the
/// current track in MILLISECONDS (converted to seconds inside the fetch script).
@MainActor
final class SpotifySource: ScriptablePlayerSource {
    init() {
        super.init(config: ScriptablePlayerConfig(
            kind: .spotify,
            bundleIdentifier: "com.spotify.client",
            appName: "Spotify",
            notificationName: "com.spotify.client.PlaybackStateChanged",
            scripts: PlayerScripts(
                fetch: SpotifyScripts.fetch,
                playPause: SpotifyScripts.playPause,
                nextTrack: SpotifyScripts.nextTrack,
                previousTrack: SpotifyScripts.previousTrack,
                seek: { seconds in SpotifyScripts.seek(to: seconds) }
            )
        ))
    }
}

// MARK: - Scripts

/// Addressed by bundle id (`application id "com.spotify.client"`), so the
/// scripts never depend on the app's display name.
private enum SpotifyScripts {
    /// One round trip: returns {state, name, artist, position (s), duration (s)}.
    /// `player state` is NOT wrapped in `try`, so permission errors (-1743) propagate.
    static let fetch = """
    if application id "com.spotify.client" is running then
    \twith timeout of 3 seconds
    \t\ttell application id "com.spotify.client"
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
    \t\t\t\t\tif x is not missing value then set dur to x / 1000.0
    \t\t\t\tend try
    \t\t\tend try
    \t\t\treturn {st, nm, ar, pos, dur}
    \t\tend tell
    \tend timeout
    else
    \treturn {"notrunning", "", "", 0.0, 0.0}
    end if
    """

    static let playPause = """
    if application id "com.spotify.client" is running then
    \twith timeout of 3 seconds
    \t\ttell application id "com.spotify.client" to playpause
    \tend timeout
    end if
    return true
    """

    static let nextTrack = """
    if application id "com.spotify.client" is running then
    \twith timeout of 3 seconds
    \t\ttell application id "com.spotify.client" to next track
    \tend timeout
    end if
    return true
    """

    static let previousTrack = """
    if application id "com.spotify.client" is running then
    \twith timeout of 3 seconds
    \t\ttell application id "com.spotify.client" to previous track
    \tend timeout
    end if
    return true
    """

    static func seek(to seconds: Double) -> String {
        // String(format:) uses the POSIX locale, so the decimal separator is always ".".
        let value = String(format: "%.3f", seconds)
        return """
        if application id "com.spotify.client" is running then
        \twith timeout of 3 seconds
        \t\ttell application id "com.spotify.client" to set player position to \(value)
        \tend timeout
        end if
        return true
        """
    }
}
