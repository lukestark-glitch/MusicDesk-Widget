import AppKit
import SwiftUI

/// Owns the single settings window ("MusicDesk – Einstellungen").
///
/// The NSWindow is created once and kept (so the frame autosave name stays
/// unique); its SwiftUI content is dropped when the window closes, so the
/// live preview does not keep running in the background.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let autosaveName = "MusicDeskSettingsWindow"
    private static let defaultContentSize = NSSize(width: 520, height: 720)
    private static let minimumContentSize = NSSize(width: 520, height: 420)

    private let media: MediaManager
    private var window: NSWindow?

    init(media: MediaManager) {
        self.media = media
        super.init()
    }

    /// Shows the window (creating it on first use), activates the app and
    /// brings the window to the front.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if window.contentView == nil {
            window.contentView = makeContentView()
        }
        AppActivation.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        // An accessory app may not become active immediately (macOS 14+
        // cooperative activation): make sure the window is visible anyway.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MusicDesk – Einstellungen"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenNone]
        window.contentMinSize = Self.minimumContentSize
        window.contentMaxSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        window.contentView = makeContentView()
        window.setContentSize(Self.defaultContentSize)
        window.delegate = self
        window.center()
        // Restores the saved frame (if any) and saves future changes.
        window.setFrameAutosaveName(Self.autosaveName)
        return window
    }

    private func makeContentView() -> NSView {
        let hostingView = NSHostingView(rootView: SettingsView(media: media))
        // Only the minimum size of the SwiftUI content constrains the window;
        // the user may enlarge it freely (the Form scrolls).
        hostingView.sizingOptions = [.minSize]
        return hostingView
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        // Release the SwiftUI hierarchy after the close finished, unless the
        // window was reopened in the meantime.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, !window.isVisible else { return }
            window.contentView = nil
        }
    }
}
