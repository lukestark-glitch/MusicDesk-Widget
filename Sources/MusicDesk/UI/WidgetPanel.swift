import AppKit
import SwiftUI

/// Borderless, fully transparent, non-activating panel that sits just above
/// the desktop icons, on all Spaces, and never shows up in Cmd-Tab / Exposé cycling.
///
/// No custom initializers on purpose: the inherited NSPanel initializers are
/// used and `configureAsDesktopWidget()` applies the configuration.
final class WidgetPanel: NSPanel {
    /// Supplies the right-click menu (built fresh for every click).
    var contextMenuProvider: (() -> NSMenu?)?

    // Key status is allowed (so drags inside SwiftUI work reliably);
    // `.nonactivatingPanel` keeps the app itself from activating.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func configureAsDesktopWidget() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isFloatingPanel = false
        hidesOnDeactivate = false          // panels hide on deactivate by default
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        isReleasedWhenClosed = false
        isMovable = true                   // needed for performDrag(with:)
        isMovableByWindowBackground = false // only the title area moves the window
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    /// Right-click (or Ctrl-click) anywhere on the visible content opens the
    /// context menu. Handling it here is independent of SwiftUI's internal
    /// view hierarchy and therefore reliable.
    override func sendEvent(_ event: NSEvent) {
        let isContextClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if isContextClick, let menu = contextMenuProvider?(), let view = contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return
        }
        super.sendEvent(event)
    }
}

/// Hosting view that reacts to the first click even though the panel is
/// neither key nor active (otherwise the first click would be swallowed).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
