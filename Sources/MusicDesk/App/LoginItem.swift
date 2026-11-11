import AppKit
import Foundation
import os
import ServiceManagement

private let log = Logger(subsystem: "com.musicdesk.widget", category: "LoginItem")

/// Thin wrapper around `SMAppService.mainApp` ("open at login").
/// Errors are logged, never thrown or fatal.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// Registers or unregisters the app as login item.
    /// - Returns: true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                log.info("Registered login item (status: \(String(describing: SMAppService.mainApp.status), privacy: .public))")
            } else {
                // Unregistering a service that is not registered throws; skip it.
                guard status != .notRegistered else { return true }
                try SMAppService.mainApp.unregister()
                log.info("Unregistered login item")
            }
            return true
        } catch {
            log.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Menu toggle: enabled -> off, needs approval -> open System Settings, otherwise -> on.
    static func toggle() {
        switch status {
        case .enabled:
            setEnabled(false)
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            setEnabled(true)
            if requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    /// On the very first launch, try once to enable "open at login".
    /// Later launches respect whatever the user chose.
    static func registerOnFirstLaunchIfNeeded(settings: AppSettings) {
        guard !settings.didAttemptInitialLoginRegistration else { return }
        settings.didAttemptInitialLoginRegistration = true
        guard status != .enabled else { return }
        setEnabled(true)
    }
}
