import AppKit
import Foundation
import os

private let log = Logger(subsystem: "com.musicdesk.widget", category: "WindowPlacement")

/// Saves and restores the widget position (origin + screen).
@MainActor
enum WindowPlacement {
    /// Minimum visible part of the widget for a saved position to count as "on screen".
    private static let minimumVisibleWidth: CGFloat = 100
    private static let minimumVisibleHeight: CGFloat = 40
    /// Default distance from the bottom of the visible frame.
    private static let defaultBottomOffset: CGFloat = 120

    static func restore(_ window: NSWindow, settings: AppSettings) {
        if let saved = settings.savedWindowPosition,
           let origin = validatedOrigin(saved, size: window.frame.size) {
            window.setFrameOrigin(origin)
        } else {
            window.setFrameOrigin(defaultOrigin(for: window.frame.size))
            log.info("Using default window position")
        }
    }

    static func save(_ window: NSWindow, settings: AppSettings) {
        let frame = window.frame
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(frame) }
        settings.saveWindowPosition(SavedWindowPosition(
            origin: frame.origin,
            screenID: screen.flatMap { displayID(of: $0) },
            screenName: screen?.localizedName
        ))
    }

    /// Moves the window to the default position if it is no longer visible
    /// (e.g. after its display was disconnected).
    static func ensureVisible(_ window: NSWindow, settings: AppSettings) {
        guard !isSufficientlyVisible(window.frame) else { return }
        window.setFrameOrigin(defaultOrigin(for: window.frame.size))
        log.info("Widget was off screen; moved to default position")
    }

    // MARK: - Helpers

    private static func validatedOrigin(_ saved: SavedWindowPosition, size: NSSize) -> NSPoint? {
        let screens = NSScreen.screens
        let hasScreenInfo = saved.screenID != nil || saved.screenName != nil
        if hasScreenInfo {
            let byID = saved.screenID.map { id in screens.contains { displayID(of: $0) == id } } ?? false
            let byName = saved.screenName.map { name in screens.contains { $0.localizedName == name } } ?? false
            guard byID || byName else { return nil } // saved screen is gone
        }
        let frame = NSRect(origin: saved.origin, size: size)
        guard isSufficientlyVisible(frame) else { return nil }
        return saved.origin
    }

    private static func isSufficientlyVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let visible = screen.frame.intersection(frame)
            return !visible.isNull
                && visible.width >= min(minimumVisibleWidth, frame.width)
                && visible.height >= min(minimumVisibleHeight, frame.height)
        }
    }

    /// Centered horizontally, ~120 pt above the bottom of the main screen's visible frame.
    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.minY + defaultBottomOffset).rounded()
        )
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
