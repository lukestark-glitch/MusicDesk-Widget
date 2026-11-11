import AppKit
import Foundation

/// Builds the right-click menu of the widget. A fresh menu is built for
/// every click so all checkmarks reflect the current state.
@MainActor
final class ContextMenuController: NSObject {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "MusicDesk")
        menu.autoenablesItems = false

        // Farbe ▸ Schwarz / Weiß / Automatisch
        let colorMenu = NSMenu(title: "Farbe")
        colorMenu.autoenablesItems = false
        for mode in WidgetColorMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(selectColorMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.colorMode == mode ? .on : .off
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Farbe", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

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

        let aboutItem = NSMenuItem(title: "Über MusicDesk", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "MusicDesk beenden", action: #selector(quit(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func selectColorMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = WidgetColorMode(rawValue: raw) else { return }
        settings.colorMode = mode
    }

    @objc private func togglePositionLock(_ sender: NSMenuItem) {
        settings.positionLocked.toggle()
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        LoginItem.toggle()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        // An accessory app must be activated for the About panel to come to front.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
