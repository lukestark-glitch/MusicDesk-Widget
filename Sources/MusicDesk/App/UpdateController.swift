import AppKit
import Foundation
import os
import UserNotifications

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case downloading(progress: Double)
    case installing
    case failed(message: String)
}

/// Checks GitHub Releases for a newer MusicDesk and installs it on request.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    /// CFBundleShortVersionString of the running app.
    let currentVersion: String

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var latestVersion: String?
    @Published private(set) var lastCheck: Date?

    var isUpdateAvailable: Bool {
        guard let release = latestRelease else { return false }
        return SemVer.isNewer(release.version, than: currentVersion)
    }

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let notifiedVersionKey = "notifiedUpdateVersion"

    private var latestRelease: ReleaseInfo?
    private var timer: Timer?
    private var started = false
    private var isChecking = false
    private var isInstalling = false
    private let notificationDelegate = UpdateNotificationDelegate()

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let stored = UserDefaults.standard.double(forKey: SettingsKey.lastUpdateCheck)
        lastCheck = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    // MARK: Public API

    /// Call once at launch.
    func start() {
        guard !started else { return }
        started = true
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }
        checkIfDue()
        let timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task { @MainActor in
                UpdateController.shared.checkIfDue()
            }
        }
        timer.tolerance = 5 * 60
        self.timer = timer
    }

    /// Manual check (ignores the auto-check setting).
    func checkNow() {
        performCheck(manual: true)
    }

    /// Confirms, downloads, verifies, swaps the bundle and relaunches.
    func installUpdate() {
        guard !isInstalling else { return }
        guard let release = latestRelease, isUpdateAvailable else {
            showAlert(title: "Kein Update verfügbar",
                      text: "MusicDesk \(currentVersion) ist aktuell.", style: .informational)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let confirm = NSAlert()
        confirm.alertStyle = .informational
        confirm.messageText = "Update auf \(release.version) installieren?"
        confirm.informativeText = "MusicDesk wird neu gestartet."
        confirm.addButton(withTitle: "Installieren")
        confirm.addButton(withTitle: "Abbrechen")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        guard let bundleID = Bundle.main.bundleIdentifier else {
            fail(UpdateError.notAnAppBundle)
            return
        }
        let currentAppURL = Bundle.main.bundleURL
        let currentVersion = self.currentVersion
        let pid = ProcessInfo.processInfo.processIdentifier

        isInstalling = true
        status = .downloading(progress: 0)
        UpdateLog.logger.info("Installiere Update \(release.version, privacy: .public) von \(release.assetURL.absoluteString, privacy: .public)")

        Task { @MainActor in
            do {
                let workDir = try await UpdateInstaller.makeWorkDirectory()
                let zip = try await UpdateInstaller.download(release, into: workDir) { progress in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            UpdateController.shared.reportDownloadProgress(progress)
                        }
                    }
                }
                self.status = .installing
                let prepared = try await UpdateInstaller.prepare(
                    zipURL: zip,
                    workDirectory: workDir,
                    expectedVersion: release.version,
                    currentVersion: currentVersion,
                    bundleIdentifier: bundleID,
                    currentAppURL: currentAppURL
                )
                try await UpdateInstaller.launchHelper(prepared, waitingFor: pid)
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UpdateLog.logger.info("Beende MusicDesk für das Update")
                NSApp.terminate(nil)
            } catch {
                self.isInstalling = false
                self.fail(error)
            }
        }
    }

    // MARK: Internals

    fileprivate func handleNotificationTap() {
        if isUpdateAvailable {
            installUpdate()
        } else {
            checkNow()
        }
    }

    private func reportDownloadProgress(_ progress: Double) {
        guard case .downloading = status else { return }
        status = .downloading(progress: progress)
    }

    private func checkIfDue() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: SettingsKey.autoCheckUpdates) as? Bool ?? SettingsDefault.autoCheckUpdates
        guard enabled else { return }
        if let last = lastCheck, last <= Date(), Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        performCheck(manual: false)
    }

    private func performCheck(manual: Bool) {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        status = .checking

        Task { @MainActor in
            defer { self.isChecking = false }
            do {
                let release = try await UpdateInstaller.fetchLatestRelease()
                self.recordCheck()
                if let release, SemVer.isNewer(release.version, than: self.currentVersion) {
                    self.latestRelease = release
                    self.latestVersion = release.version
                    self.status = .available(version: release.version)
                    UpdateLog.logger.info("Update verfügbar: \(release.version, privacy: .public)")
                    self.notifyIfNeeded(version: release.version)
                } else {
                    self.latestRelease = nil
                    self.latestVersion = release?.version ?? self.currentVersion
                    self.status = .upToDate
                    UpdateLog.logger.info("Kein Update (neueste: \(release?.version ?? "–", privacy: .public))")
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                UpdateLog.logger.error("Update-Prüfung fehlgeschlagen: \(message, privacy: .public)")
                if !manual, self.isUpdateAvailable, let version = self.latestVersion {
                    // Keep showing the known update after a failed background check.
                    self.status = .available(version: version)
                } else {
                    self.status = .failed(message: message)
                }
            }
        }
    }

    private func recordCheck() {
        let now = Date()
        lastCheck = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: SettingsKey.lastUpdateCheck)
    }

    /// Posts one subtle notification per version; asks for permission only now.
    private func notifyIfNeeded(version: String) {
        let defaults = UserDefaults.standard
        let key = Self.notifiedVersionKey
        guard defaults.string(forKey: key) != version else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                UpdateLog.logger.error("Mitteilungen nicht erlaubt: \(error.localizedDescription, privacy: .public)")
            }
            guard granted else {
                UpdateLog.logger.info("Mitteilungen abgelehnt – keine Update-Mitteilung")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "MusicDesk \(version) verfügbar"
            content.body = "Rechtsklick auf das Widget → „Update installieren …“"
            content.userInfo = ["version": version]
            let request = UNNotificationRequest(identifier: "musicdesk-update-\(version)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    UpdateLog.logger.error("Mitteilung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
                } else {
                    UserDefaults.standard.set(version, forKey: key)
                }
            }
        }
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        UpdateLog.logger.error("Update fehlgeschlagen: \(message, privacy: .public)")
        status = .failed(message: message)
        showAlert(title: "Update fehlgeschlagen",
                  text: message + "\n\nMusicDesk bleibt unverändert. Manuelle Installation: \(UpdateInstaller.releasesPageURL.absoluteString)",
                  style: .warning)
    }

    private func showAlert(title: String, text: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Notification delegate

/// Separate, non-isolated delegate; hops to the main actor for UI work.
private final class UpdateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let isUpdate = response.notification.request.identifier.hasPrefix("musicdesk-update-")
            && response.actionIdentifier == UNNotificationDefaultActionIdentifier
        guard isUpdate else { return }
        // Don't block the system's completion on the confirmation alert.
        Task { @MainActor in
            UpdateController.shared.handleNotificationTap()
        }
    }
}
