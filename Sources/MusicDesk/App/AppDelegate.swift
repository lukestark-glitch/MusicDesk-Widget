import AppKit
import Foundation
import os
import SwiftUI

private let log = Logger(subsystem: "com.musicdesk.widget", category: "App")

/// Owns the model objects, the desktop widget window and the settings window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Created in applicationDidFinishLaunching so `init()` stays trivial.
    private var settings: AppSettings?
    private var media: MediaManager?
    private var panel: WidgetPanel?
    private var menuController: ContextMenuController?
    private var settingsWindowController: SettingsWindowController?
    private var terminationSignalSource: DispatchSourceSignal?
    private var fullScreenObserver: FullScreenObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        let media = MediaManager()
        let menuController = ContextMenuController(settings: settings) { [weak self] in
            self?.openSettings()
        }
        self.settings = settings
        self.media = media
        self.menuController = menuController

        installMainMenu()

        // Window
        let panel = WidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: WidgetLayout.width, height: WidgetLayout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configureAsDesktopWidget()

        let hostingView = FirstMouseHostingView(rootView: LiveWidgetView(media: media))
        hostingView.frame = NSRect(x: 0, y: 0, width: WidgetLayout.width, height: WidgetLayout.height)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.contextMenuProvider = { [weak menuController] in
            menuController?.makeMenu()
        }
        panel.keyEquivalentHandler = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
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

        // Hide the widget while another app is in full-screen mode on its
        // screen (the panel joins all Spaces, including full-screen ones).
        let fullScreenObserver = FullScreenObserver(window: panel)
        fullScreenObserver.onChange = { [weak panel] isFullScreen in
            guard let panel else { return }
            panel.ignoresMouseEvents = isFullScreen
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = isFullScreen ? 0 : 1
            }
        }
        fullScreenObserver.start()
        self.fullScreenObserver = fullScreenObserver

        installTerminationSignalHandler()
        media.start()
        UpdateController.shared.start()
        LoginItem.registerOnFirstLaunchIfNeeded(settings: settings)
        log.info("MusicDesk launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Also terminates the mediaremote-adapter child process.
        media?.stop()
        fullScreenObserver?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it runs shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// `pkill`/`kill` (install.sh, uninstall.sh) send SIGTERM, which would end
    /// the process without `applicationWillTerminate` – and leave the adapter's
    /// perl child running. Route SIGTERM through a normal termination instead.
    private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        terminationSignalSource = source
    }

    // MARK: - Settings

    private func openSettings() {
        guard let media else { return }
        let controller: SettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            controller = SettingsWindowController(media: media)
            settingsWindowController = controller
        }
        controller.show()
    }

    @objc private func showSettings(_ sender: Any?) {
        openSettings()
    }

    @objc private func showAbout(_ sender: Any?) {
        AppActivation.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    /// ⌘, and ⌘Q while the widget panel is key (the app may be inactive then,
    /// so the main menu would not receive the shortcut).
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard flags == .command else { return false }
        switch event.charactersIgnoringModifiers {
        case ",":
            openSettings()
            return true
        case "q":
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }

    // MARK: - Main menu

    /// The app is an agent (no menu bar shown), but NSApp.mainMenu still
    /// provides the key equivalents whenever the app is active, e.g. while
    /// the settings window is in front: ⌘, ⌘Q, ⌘W and the edit shortcuts
    /// for the hex text field.
    private func installMainMenu() {
        let mainMenu = NSMenu(title: "MainMenu")

        // App menu
        let appMenu = NSMenu(title: "MusicDesk")
        let about = NSMenuItem(title: "Über MusicDesk", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: "Einstellungen …", action: #selector(showSettings(_:)), keyEquivalent: ",")
        prefs.keyEquivalentModifierMask = [.command]
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "MusicDesk beenden", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        appMenu.addItem(quit)
        let appItem = NSMenuItem(title: "MusicDesk", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu (nil target = responder chain, i.e. the focused text field)
        let editMenu = NSMenu(title: "Bearbeiten")
        editMenu.addItem(NSMenuItem(title: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(title: "Bearbeiten", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // Window menu (the borderless widget panel is not closable, so ⌘W
        // only affects the settings window).
        let windowMenu = NSMenu(title: "Fenster")
        windowMenu.addItem(NSMenuItem(title: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        let windowItem = NSMenuItem(title: "Fenster", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
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
