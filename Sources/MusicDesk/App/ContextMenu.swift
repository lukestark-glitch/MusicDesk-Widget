import AppKit
import Foundation

/// Builds the right-click menu of the widget. A fresh menu is built for
/// every click so all checkmarks reflect the current state.
/// Colors and all other appearance options live in the settings window.
@MainActor
final class ContextMenuController: NSObject {
    private let settings: AppSettings
    private let openSettings: @MainActor () -> Void

    init(settings: AppSettings, openSettings: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        super.init()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "MusicDesk")
        menu.autoenablesItems = false

        let updates = UpdateController.shared
        if updates.isUpdateAvailable {
            let version = updates.latestVersion.map { " (\($0))" } ?? ""
            let updateItem = NSMenuItem(title: "Update installieren …" + version, action: #selector(installUpdate(_:)), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        let lockItem = NSMenuItem(title: "Position sperren", action: #selector(togglePositionLock(_:)), keyEquivalent: "")
        lockItem.target = self
        lockItem.state = settings.positionLocked ? .on : .off
        menu.addItem(lockItem)

        let loginItem = NSMenuItem(title: "Beim Login starten", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        switch LoginItem.status {
        case .enabled:
            loginItem.state = .on
        case .requiresApproval:
            // Registered but waiting for approval in System Settings.
            loginItem.state = .mixed
        default:
            loginItem.state = .off
        }
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // Shows ⌘, as hint; the shortcut itself is handled by the main menu
        // and by WidgetPanel.performKeyEquivalent.
        let settingsItem = NSMenuItem(title: "Einstellungen …", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "Über MusicDesk", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "MusicDesk beenden", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func installUpdate(_ sender: NSMenuItem) {
        UpdateController.shared.installUpdate()
    }

    @objc private func togglePositionLock(_ sender: NSMenuItem) {
        settings.positionLocked.toggle()
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        LoginItem.toggle()
    }

    @objc private func showSettings(_ sender: NSMenuItem) {
        openSettings()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        AppActivation.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

/// Brings the (accessory) app to the front, e.g. before showing a window.
@MainActor
enum AppActivation {
    static func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
