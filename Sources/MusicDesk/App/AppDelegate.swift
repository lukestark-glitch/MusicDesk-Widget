import AppKit
import Foundation
import os
import SwiftUI

private let log = Logger(subsystem: "com.musicdesk.widget", category: "App")

/// Owns the model objects and the desktop widget window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Created in applicationDidFinishLaunching so `init()` stays trivial.
    private var settings: AppSettings?
    private var music: MusicController?
    private var panel: WidgetPanel?
    private var menuController: ContextMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let music = MusicController()
        let menuController = ContextMenuController(settings: settings)
        self.settings = settings
        self.music = music
        self.menuController = menuController

        // Window
        let panel = WidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: WidgetLayout.width, height: WidgetLayout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsDesktopWidget()

        let hostingView = FirstMouseHostingView(rootView: WidgetView(music: music, settings: settings))
        hostingView.frame = NSRect(x: 0, y: 0, width: WidgetLayout.width, height: WidgetLayout.height)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.contextMenuProvider = { [weak menuController] in
            menuController?.makeMenu()
        }

        // Restore the position before observing moves, so restoring does not re-save.
        WindowPlacement.restore(panel, settings: settings)
        self.panel = panel

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // The app is never active, so order front regardless of activation.
        panel.orderFrontRegardless()

        music.start()
        LoginItem.registerOnFirstLaunchIfNeeded(settings: settings)
        log.info("MusicDesk launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        music?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Window position

    @objc private func windowDidMove(_ notification: Notification) {
        guard let panel, let settings else { return }
        WindowPlacement.save(panel, settings: settings)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        // A display was removed or rearranged: pull the widget back on screen if needed.
        guard let panel, let settings else { return }
        WindowPlacement.ensureVisible(panel, settings: settings)
    }
}
