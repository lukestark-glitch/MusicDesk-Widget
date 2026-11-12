import Foundation
import os

/// Shared logger for the updater (UpdateController + UpdateInstaller).
enum UpdateLog {
    static let logger = Logger(subsystem: "com.musicdesk.widget", category: "Update")
}

// MARK: - Errors

/// Updater errors with German, user-facing messages.
enum UpdateError: LocalizedError, Sendable {
    case network(String)
    case httpStatus(Int)
    case rateLimited
    case invalidResponse
    case missingAsset(version: String)
    case download(String)
    case unzip(String)
    case appNotFound
    case wrongBundleIdentifier(found: String)
    case wrongVersion(found: String, expected: String)
    case notNewer(found: String, current: String)
    case signatureInvalid(String)
    case notAnAppBundle
    case notWritable(path: String)
    case targetOccupied(path: String)
    case newerVersionInstalled(version: String, path: String)
    case copyFailed(String)
    case helper(String)

    var errorDescription: String? {
        switch self {
        case .network(let detail):
            return "Keine Verbindung zu GitHub möglich (\(detail))."
        case .httpStatus(let code):
            return "GitHub antwortete mit Status \(code)."
        case .rateLimited:
            return "GitHub-Anfragelimit erreicht. Bitte später erneut versuchen."
        case .invalidResponse:
            return "Die Antwort von GitHub konnte nicht gelesen werden."
        case .missingAsset(let version):
            return "Version \(version) gefunden, aber kein passendes Download-Archiv (MusicDesk-….zip)."
        case .download(let detail):
            return "Download fehlgeschlagen (\(detail))."
        case .unzip(let detail):
            return "Das Archiv konnte nicht entpackt werden (\(detail))."
        case .appNotFound:
            return "Im Archiv wurde keine MusicDesk.app gefunden."
        case .wrongBundleIdentifier(let found):
            return "Die geladene App hat eine unerwartete Kennung (\(found))."
        case .wrongVersion(let found, let expected):
            return "Die geladene App hat Version \(found) statt \(expected)."
        case .notNewer(let found, let current):
            return "Die geladene Version \(found) ist nicht neuer als \(current)."
        case .signatureInvalid(let detail):
            return "Die Signatur der geladenen App ist ungültig (\(detail))."
        case .notAnAppBundle:
            return "MusicDesk läuft nicht aus einer App (MusicDesk.app). Bitte das Update manuell installieren."
        case .notWritable(let path):
            return "Keine Schreibrechte für „\(path)“. Bitte das Update manuell installieren: ZIP von GitHub laden und MusicDesk.app ersetzen."
        case .targetOccupied(let path):
            return "Unter „\(path)“ liegt eine andere App mit demselben Namen. Bitte sie umbenennen oder entfernen und es erneut versuchen."
        case .newerVersionInstalled(let version, let path):
            return "Unter „\(path)“ ist bereits MusicDesk \(version) installiert. Bitte diese Version starten."
        case .copyFailed(let detail):
            return "MusicDesk konnte nicht kopiert werden (\(detail))."
        case .helper(let detail):
            return "Das Update konnte nicht gestartet werden (\(detail))."
        }
    }
}

// MARK: - Versions

/// Lenient semantic-version handling: numeric components, missing = 0,
/// prerelease/build suffixes ("-beta.1", "+5") are ignored.
enum SemVer {
    /// "v1.2.0" → "1.2.0" (whitespace trimmed, leading v/V removed).
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" { s.removeFirst() }
        return s
    }

    static func components(_ version: String) -> [Int] {
        var core = normalize(version)
        if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" || $0 == " " }) {
            core = String(core[..<cut])
        }
        return core.split(separator: ".", omittingEmptySubsequences: false).map { part in
            let digits = part.prefix(while: { $0.isASCII && $0.isNumber })
            return Int(digits) ?? 0
        }
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let ca = components(a)
        let cb = components(b)
        for i in 0..<max(ca.count, cb.count) {
            let x = i < ca.count ? ca[i] : 0
            let y = i < cb.count ? cb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }
}

// MARK: - Release info

struct ReleaseInfo: Sendable, Equatable {
    let version: String      // without leading "v"
    let tag: String
    let assetName: String
    let assetURL: URL
    let assetSize: Int64
}

/// Result of a successful preparation: everything verified, nothing installed yet.
struct PreparedUpdate: Sendable {
    let workDirectory: URL
    let newAppURL: URL
    let targetAppURL: URL
    let backupAppURL: URL
    /// Opened by the helper if the installation fails (the copy the user ran).
    let fallbackAppURL: URL
    /// Old copy outside the Applications folders that the new app moves to the
    /// Trash after a successful install (nil = nothing to clean up).
    let oldCopyURL: URL?
    let scriptURL: URL
    let logURL: URL
}

/// Where an update (or "In Programme verschieben") installs the app.
struct InstallPlan: Sendable {
    let target: URL
    let fallback: URL
    let oldCopy: URL?
    /// Target differs from the copy the user ran (e.g. ~/Downloads → /Applications).
    var relocates: Bool { oldCopy != nil || !AppLocation.samePath(target, fallback) }
}

// MARK: - Installer (all blocking work runs off the main thread)

enum UpdateInstaller {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/lukestark-glitch/MusicDesk-Widget/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/lukestark-glitch/MusicDesk-Widget/releases")!
    static let appName = "MusicDesk.app"

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            let size: Int64?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
                case size
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }
    }

    // MARK: Check

    /// Latest published (non-draft, non-prerelease) release, or nil if there is none.
    static func fetchLatestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MusicDesk-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        let data = result.0
        let response = result.1
        guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 404: return nil  // no release published yet
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.httpStatus(http.statusCode)
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            UpdateLog.logger.error("Release-JSON nicht lesbar: \(error.localizedDescription, privacy: .public)")
            throw UpdateError.invalidResponse
        }
        guard !release.draft, !release.prerelease else {
            UpdateLog.logger.info("Neuestes Release ist Entwurf/Vorabversion – ignoriert")
            return nil
        }
        let version = SemVer.normalize(release.tagName)
        guard !version.isEmpty else { throw UpdateError.invalidResponse }

        let pattern = "^MusicDesk-.*\\.zip$"
        guard let asset = release.assets.first(where: { $0.name.range(of: pattern, options: .regularExpression) != nil }),
              let url = URL(string: asset.browserDownloadURL),
              url.scheme == "https"
        else {
            throw UpdateError.missingAsset(version: version)
        }
        return ReleaseInfo(version: version, tag: release.tagName, assetName: asset.name,
                           assetURL: url, assetSize: asset.size ?? 0)
    }

    // MARK: Download

    /// Creates a fresh, empty work directory in the temporary folder.
    static func makeWorkDirectory() async throws -> URL {
        try await offMain {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MusicDesk-Update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    /// Downloads the asset into `workDirectory/update.zip`. `progress` (0…1) is
    /// called from a background queue.
    static func download(_ release: ReleaseInfo, into workDirectory: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = workDirectory.appendingPathComponent("update.zip")
        let delegate = DownloadDelegate(destination: destination, expectedSize: release.assetSize, progress: progress)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 15 * 60
        config.httpAdditionalHeaders = ["User-Agent": "MusicDesk-Updater"]
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: release.assetURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let task = session.downloadTask(with: request)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            delegate.setContinuation(continuation)
            task.resume()
        }
    }

    // MARK: Prepare (unzip + verify + helper script)

    /// Unzips, verifies and writes the helper script. Never touches the
    /// installed app.
    static func prepare(zipURL: URL, workDirectory: URL, expectedVersion: String,
                        currentVersion: String, bundleIdentifier: String,
                        currentAppURL: URL) async throws -> PreparedUpdate {
        try await offMain {
            try prepareSync(zipURL: zipURL, workDirectory: workDirectory, expectedVersion: expectedVersion,
                            currentVersion: currentVersion, bundleIdentifier: bundleIdentifier,
                            currentAppURL: currentAppURL)
        }
    }

    private static func prepareSync(zipURL: URL, workDirectory: URL, expectedVersion: String,
                                    currentVersion: String, bundleIdentifier: String,
                                    currentAppURL: URL) throws -> PreparedUpdate {
        // Target checks first – cheap and the most likely failure. A
        // translocated app outside the Applications folders is installed to
        // /Applications (or ~/Applications) instead of its read-only copy.
        let plan = try installPlan(currentAppURL: currentAppURL, moveToApplications: false)
        UpdateLog.logger.info("Update-Ziel: \(plan.target.path, privacy: .public)")

        // Unzip.
        let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        let unzip = try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extracted.path])
        guard unzip.status == 0 else { throw UpdateError.unzip(unzip.output.isEmpty ? "ditto \(unzip.status)" : unzip.output) }

        // Locate MusicDesk.app (top level or one folder deep).
        guard let newApp = locateApp(in: extracted) else { throw UpdateError.appNotFound }
        UpdateLog.logger.info("Neue App gefunden: \(newApp.path, privacy: .public)")

        // Info.plist checks.
        let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: plistURL),
              let plist = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
        else { throw UpdateError.appNotFound }
        let foundID = plist["CFBundleIdentifier"] as? String ?? "–"
        guard foundID == bundleIdentifier else { throw UpdateError.wrongBundleIdentifier(found: foundID) }
        let foundVersion = plist["CFBundleShortVersionString"] as? String ?? "–"
        guard SemVer.compare(foundVersion, expectedVersion) == .orderedSame else {
            throw UpdateError.wrongVersion(found: foundVersion, expected: expectedVersion)
        }
        guard SemVer.isNewer(foundVersion, than: currentVersion) else {
            throw UpdateError.notNewer(found: foundVersion, current: currentVersion)
        }

        // Signature (ad-hoc is fine, but it must be intact).
        let sign = try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
        UpdateLog.logger.info("codesign --verify: \(sign.status) \(sign.output, privacy: .public)")
        guard sign.status == 0 else {
            throw UpdateError.signatureInvalid(sign.output.isEmpty ? "codesign \(sign.status)" : sign.output)
        }

        // Never replace a foreign app or a newer MusicDesk at a new target.
        try checkExistingTarget(plan, bundleIdentifier: bundleIdentifier, installingVersion: foundVersion)

        removeQuarantine(newApp)
        return try finishPreparation(plan: plan, newApp: newApp, workDirectory: workDirectory)
    }

    /// Prepares "In Programme verschieben": copies the running bundle into the
    /// work directory, removes the quarantine and writes the helper script.
    /// Never touches the installed app.
    static func prepareMove(workDirectory: URL, currentVersion: String, bundleIdentifier: String,
                            currentAppURL: URL) async throws -> PreparedUpdate {
        try await offMain {
            try prepareMoveSync(workDirectory: workDirectory, currentVersion: currentVersion,
                                bundleIdentifier: bundleIdentifier, currentAppURL: currentAppURL)
        }
    }

    private static func prepareMoveSync(workDirectory: URL, currentVersion: String, bundleIdentifier: String,
                                        currentAppURL: URL) throws -> PreparedUpdate {
        let plan = try installPlan(currentAppURL: currentAppURL, moveToApplications: true)
        UpdateLog.logger.info("Verschiebe-Ziel: \(plan.target.path, privacy: .public)")
        try checkExistingTarget(plan, bundleIdentifier: bundleIdentifier, installingVersion: currentVersion)

        // Copy the running bundle (for a translocated app this is the
        // read-only mirror of the original – readable without extra access).
        let staging = workDirectory.appendingPathComponent("staged", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let newApp = staging.appendingPathComponent(appName, isDirectory: true)
        let source = currentAppURL.standardizedFileURL
        guard source.pathExtension == "app" else { throw UpdateError.notAnAppBundle }
        let copy = try run("/usr/bin/ditto", [source.path, newApp.path])
        guard copy.status == 0 else { throw UpdateError.copyFailed(copy.output.isEmpty ? "ditto \(copy.status)" : copy.output) }

        let foundID = Self.bundleIdentifier(of: newApp) ?? "–"
        guard foundID == bundleIdentifier else { throw UpdateError.wrongBundleIdentifier(found: foundID) }
        let sign = try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
        UpdateLog.logger.info("codesign --verify (Kopie): \(sign.status) \(sign.output, privacy: .public)")
        guard sign.status == 0 else {
            throw UpdateError.signatureInvalid(sign.output.isEmpty ? "codesign \(sign.status)" : sign.output)
        }

        removeQuarantine(newApp)
        return try finishPreparation(plan: plan, newApp: newApp, workDirectory: workDirectory)
    }

    // MARK: Target selection

    /// Decides where to install.
    /// - Translocated, original in /Applications or ~/Applications: replace the original.
    /// - Translocated, original elsewhere (Downloads, Desktop …) or unknown:
    ///   install to /Applications (writable) or ~/Applications; the original
    ///   is moved to the Trash afterwards.
    /// - Not translocated: replace in place – unless `moveToApplications` and
    ///   the app is outside the Applications folders.
    static func installPlan(currentAppURL: URL, moveToApplications: Bool) throws -> InstallPlan {
        let location = AppLocation.detect(currentAppURL)
        guard location.runningURL.pathExtension == "app" else { throw UpdateError.notAnAppBundle }
        UpdateLog.logger.info("App-Ort: \(location.runningURL.path, privacy: .public), translociert: \(location.isTranslocated), Original: \(location.originalURL?.path ?? "unbekannt", privacy: .public)")

        let relocate: Bool
        if location.isTranslocated {
            relocate = !location.isInApplicationsFolder
        } else {
            relocate = moveToApplications && !location.isInApplicationsFolder
        }

        if relocate {
            let target = try AppLocation.applicationsDestination(appName: appName)
            let fallback = location.originalURL ?? location.runningURL
            var oldCopy = location.originalURL
            if let old = oldCopy, AppLocation.samePath(old, target) || AppLocation.isInApplicationsFolder(old) {
                oldCopy = nil
            }
            return InstallPlan(target: target, fallback: fallback, oldCopy: oldCopy)
        }

        // In place: the original (translocated) or the running bundle.
        guard let original = location.originalURL else { throw UpdateError.notWritable(path: location.runningURL.path) }
        let target = original.resolvingSymlinksInPath()
        guard target.pathExtension == "app" else { throw UpdateError.notAnAppBundle }
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path), fm.isWritableFile(atPath: target.path) else {
            throw UpdateError.notWritable(path: parent.path)
        }
        return InstallPlan(target: target, fallback: target, oldCopy: nil)
    }

    /// An existing bundle at a new target must be MusicDesk and not newer
    /// than what is being installed.
    private static func checkExistingTarget(_ plan: InstallPlan, bundleIdentifier: String,
                                            installingVersion: String) throws {
        guard plan.relocates, FileManager.default.fileExists(atPath: plan.target.path) else { return }
        guard Self.bundleIdentifier(of: plan.target) == bundleIdentifier else {
            throw UpdateError.targetOccupied(path: plan.target.path)
        }
        if let existing = bundleVersion(of: plan.target), SemVer.isNewer(existing, than: installingVersion) {
            throw UpdateError.newerVersionInstalled(version: existing, path: plan.target.path)
        }
    }

    private static func finishPreparation(plan: InstallPlan, newApp: URL, workDirectory: URL) throws -> PreparedUpdate {
        let scriptURL = workDirectory.appendingPathComponent("install-update.sh")
        let logURL = workDirectory.appendingPathComponent("install-update.log")
        try helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        return PreparedUpdate(
            workDirectory: workDirectory,
            newAppURL: newApp,
            targetAppURL: plan.target,
            backupAppURL: workDirectory.appendingPathComponent("MusicDesk-old.app", isDirectory: true),
            fallbackAppURL: plan.fallback,
            oldCopyURL: plan.oldCopy,
            scriptURL: scriptURL,
            logURL: logURL
        )
    }

    /// Failure is harmless (e.g. attribute not present).
    private static func removeQuarantine(_ app: URL) {
        guard let xattr = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path]) else { return }
        if xattr.status != 0 {
            UpdateLog.logger.debug("xattr: \(xattr.status) \(xattr.output, privacy: .public)")
        }
    }

    private static func infoPlist(of app: URL) -> [String: Any]? {
        let url = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    static func bundleIdentifier(of app: URL) -> String? {
        infoPlist(of: app)?["CFBundleIdentifier"] as? String
    }

    static func bundleVersion(of app: URL) -> String? {
        infoPlist(of: app)?["CFBundleShortVersionString"] as? String
    }

    // MARK: Old copy cleanup

    /// Moves the copy the user ran before an update/move to the Trash – only if
    /// this app is now running non-translocated from an Applications folder,
    /// has the expected version and the old copy is a MusicDesk bundle outside
    /// the Applications folders. Call off the main thread.
    static func trashOldCopy(path: String, expectedVersion: String, currentVersion: String,
                             bundleIdentifier: String, runningAppURL: URL) {
        let fm = FileManager.default
        let old = URL(fileURLWithPath: path).standardizedFileURL
        let location = AppLocation.detect(runningAppURL)
        guard SemVer.compare(currentVersion, expectedVersion) == .orderedSame,
              !location.isTranslocated, location.isInApplicationsFolder,
              old.pathExtension == "app",
              !AppLocation.isInApplicationsFolder(old),
              !AppLocation.samePath(old, location.runningURL),
              fm.fileExists(atPath: old.path),
              Self.bundleIdentifier(of: old) == bundleIdentifier
        else {
            UpdateLog.logger.info("Alte Kopie bleibt liegen: \(old.path, privacy: .public)")
            return
        }
        do {
            try fm.trashItem(at: old, resultingItemURL: nil)
            UpdateLog.logger.info("Alte Kopie in den Papierkorb gelegt: \(old.path, privacy: .public)")
        } catch {
            UpdateLog.logger.error("Alte Kopie nicht in den Papierkorb gelegt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func locateApp(in directory: URL) -> URL? {
        let fm = FileManager.default
        func isRealDirectory(_ url: URL) -> Bool {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        let direct = directory.appendingPathComponent(appName, isDirectory: true)
        if isRealDirectory(direct) { return direct }
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return nil
        }
        for child in children where child.lastPathComponent != "__MACOSX" && isRealDirectory(child) {
            let nested = child.appendingPathComponent(appName, isDirectory: true)
            if isRealDirectory(nested) { return nested }
        }
        return nil
    }

    // MARK: Helper launch

    /// Starts the detached helper which waits for `pid` to exit, swaps the
    /// bundles (restoring the old one on failure) and reopens the app.
    static func launchHelper(_ prepared: PreparedUpdate, waitingFor pid: Int32) async throws {
        try await offMain {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = [
                "/bin/sh", prepared.scriptURL.path,
                String(pid),
                prepared.targetAppURL.path,
                prepared.newAppURL.path,
                prepared.backupAppURL.path,
                prepared.logURL.path,
                prepared.fallbackAppURL.path,
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.currentDirectoryURL = prepared.workDirectory
            do {
                try process.run()
            } catch {
                throw UpdateError.helper(error.localizedDescription)
            }
            UpdateLog.logger.info("Update-Helfer gestartet (pid \(process.processIdentifier)), Log: \(prepared.logURL.path, privacy: .public)")
        }
    }

    /// $1 pid, $2 target app, $3 new app, $4 backup path, $5 log file,
    /// $6 app to reopen if the installation fails (the copy the user ran).
    private static let helperScript = """
    #!/bin/sh
    PID="$1"
    TARGET="$2"
    NEW="$3"
    OLD="$4"
    LOG="$5"
    FALLBACK="$6"
    exec >>"$LOG" 2>&1
    reopen_previous() {
        if [ -n "$FALLBACK" ] && [ -d "$FALLBACK" ]; then
            /usr/bin/open "$FALLBACK"
        elif [ -d "$TARGET" ]; then
            /usr/bin/open "$TARGET"
        fi
    }
    echo "MusicDesk-Update: warte auf Prozess $PID"
    echo "Ziel: $TARGET"
    i=0
    while kill -0 "$PID" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -gt 60 ]; then
            echo "Abbruch: MusicDesk wurde nicht beendet"
            exit 1
        fi
        sleep 0.5
    done
    if [ ! -d "$NEW" ]; then
        echo "Neue App fehlt: $NEW"
        reopen_previous
        exit 1
    fi
    HAD_TARGET=0
    /bin/rm -rf "$OLD"
    if [ -e "$TARGET" ]; then
        if ! /bin/mv "$TARGET" "$OLD"; then
            echo "Alte App konnte nicht verschoben werden"
            reopen_previous
            exit 1
        fi
        HAD_TARGET=1
    fi
    if /bin/mv "$NEW" "$TARGET"; then
        echo "Neue App per mv installiert"
    else
        /bin/rm -rf "$TARGET"
        if /usr/bin/ditto "$NEW" "$TARGET"; then
            echo "Neue App per ditto installiert"
        else
            echo "Installation fehlgeschlagen – stelle alte App wieder her"
            /bin/rm -rf "$TARGET"
            if [ "$HAD_TARGET" = 1 ]; then
                /bin/mv "$OLD" "$TARGET" || /usr/bin/ditto "$OLD" "$TARGET"
            fi
            reopen_previous
            exit 1
        fi
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$TARGET" || echo "xattr am Ziel: nichts zu entfernen"
    /usr/bin/open "$TARGET"
    echo "Fertig"
    exit 0

    """

    // MARK: Utilities

    /// Runs a tool synchronously (call off-main), stdout+stderr combined.
    static func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Read to EOF before waiting so a full pipe cannot deadlock.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    /// Runs blocking work on a global queue.
    static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let expectedSize: Int64
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var finishedFile: URL?
    private var finishError: Error?
    private var lastReported: Double = -1

    init(destination: URL, expectedSize: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        guard total > 0 else { return }
        let value = min(1, max(0, Double(totalBytesWritten) / Double(total)))
        lock.lock()
        let shouldReport = value - lastReported >= 0.01 || value >= 1
        if shouldReport { lastReported = value }
        lock.unlock()
        if shouldReport { progress(value) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temporary file is deleted after this returns – move it now.
        var file: URL?
        var failure: Error?
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = UpdateError.download("HTTP \(http.statusCode)")
        } else {
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: location, to: destination)
                file = destination
            } catch {
                failure = UpdateError.download(error.localizedDescription)
            }
        }
        lock.lock()
        finishedFile = file
        finishError = failure
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let file = finishedFile
        let failure = finishError
        lock.unlock()
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: UpdateError.download(error.localizedDescription))
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if let file {
            continuation.resume(returning: file)
        } else {
            continuation.resume(throwing: UpdateError.download("keine Datei erhalten"))
        }
    }
}
