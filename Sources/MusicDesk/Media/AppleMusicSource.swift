import Foundation

/// Apple Music (com.apple.Music) via AppleScript – the 1.0 `MusicController`
/// behaviour, now as a `MediaSource`. See `ScriptablePlayerSource`.
@MainActor
final class AppleMusicSource: ScriptablePlayerSource {
    init() {
        super.init(config: ScriptablePlayerConfig(
            kind: .appleMusic,
            bundleIdentifier: "com.apple.Music",
            appName: "Apple Music",
            notificationName: "com.apple.Music.playerInfo",
            scripts: PlayerScripts(
                fetch: AppleMusicScripts.fetch,
                playPause: AppleMusicScripts.playPause,
                nextTrack: AppleMusicScripts.nextTrack,
                previousTrack: AppleMusicScripts.previousTrack,
                seek: { seconds in AppleMusicScripts.seek(to: seconds) }
            )
        ))
    }
}

// MARK: - Scripts

private enum AppleMusicScripts {
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
