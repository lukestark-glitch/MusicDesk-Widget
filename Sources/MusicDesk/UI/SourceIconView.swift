import AppKit
import SwiftUI

/// Small icon of the app that is playing (e.g. Music, Spotify, Safari).
/// Falls back to the source's SF Symbol when no app icon can be found.
@MainActor
struct SourceIconView: View {
    let state: NowPlaying
    let color: Color
    let size: CGFloat

    init(state: NowPlaying, color: Color, size: CGFloat = 22) {
        self.state = state
        self.color = color
        self.size = size
    }

    var body: some View {
        Group {
            if let image = AppIconCache.icon(forBundleIdentifier: bundleIdentifier) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: state.source?.symbolName ?? "music.note")
                    .font(.system(size: size * 0.75, weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The playing app (system source) first, else the source's player app.
    private var bundleIdentifier: String? {
        if let id = state.appBundleIdentifier, !id.isEmpty { return id }
        return state.source?.bundleIdentifier
    }
}

/// Caches app icons by bundle id (LaunchServices lookups are not free and
/// the widget re-renders on every state update).
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var misses: Set<String> = []

    static func icon(forBundleIdentifier bundleIdentifier: String?) -> NSImage? {
        guard let id = bundleIdentifier, !id.isEmpty else { return nil }
        if let cached = icons[id] { return cached }
        if misses.contains(id) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            misses.insert(id)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[id] = image
        return image
    }
}
