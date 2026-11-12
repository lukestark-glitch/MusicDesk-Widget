import Darwin
import Foundation

/// Where the running app lives – including macOS "App Translocation".
///
/// A quarantined app that was not moved with the Finder (e.g. started straight
/// from "Downloads") is run by macOS from a random, read-only copy below
/// `/private/var/folders/…/AppTranslocation/<UUID>/d/`. The updater cannot
/// replace that copy, so it has to know the original location instead.
struct AppLocation: Sendable {
    /// `Bundle.main.bundleURL` (possibly the translocated copy).
    let runningURL: URL
    let isTranslocated: Bool
    /// The bundle the user sees in the Finder. Equals `runningURL` when not
    /// translocated; nil when translocated and the original is unknown.
    let originalURL: URL?

    /// True when the user-visible bundle lies in /Applications or ~/Applications
    /// (or a subfolder). Unknown original → false.
    var isInApplicationsFolder: Bool {
        guard let originalURL else { return false }
        return AppLocation.isInApplicationsFolder(originalURL)
    }

    /// The start-up hint and "In Programme verschieben" apply.
    var shouldOfferMove: Bool {
        isTranslocated || !isInApplicationsFolder
    }

    // MARK: Detection

    static func detect(_ bundleURL: URL = Bundle.main.bundleURL) -> AppLocation {
        let running = bundleURL.standardizedFileURL
        var translocated = looksTranslocated(running)
        var original: URL?

        if let api = TranslocationAPI.load() {
            var flag = false
            if api.isTranslocated(running as CFURL, &flag, nil), flag {
                translocated = true
            }
            if translocated, let created = api.originalPath(running as CFURL, nil) {
                let url = (created.takeRetainedValue() as URL).standardizedFileURL
                if url.isFileURL, !looksTranslocated(url) {
                    original = url
                }
            }
        }

        if !translocated { original = running }
        return AppLocation(runningURL: running, isTranslocated: translocated, originalURL: original)
    }

    private static func looksTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    // MARK: Applications folders

    static var systemApplicationsFolder: URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    static var userApplicationsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return [systemApplicationsFolder, userApplicationsFolder].contains { folder in
            path.hasPrefix(normalizedPath(folder) + "/")
        }
    }

    /// Case-insensitive comparison (APFS/HFS+ default) after resolving
    /// symlinks in the parent folders.
    static func samePath(_ a: URL, _ b: URL) -> Bool {
        normalizedPath(a) == normalizedPath(b)
    }

    /// Only the parent folders are resolved: the item itself may be a symlink
    /// (e.g. /Applications/Safari.app) and still count as being in that folder.
    private static func normalizedPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        var path: String
        if name.isEmpty || name == "/" {
            path = standardized.path
        } else {
            path = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(name).path
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.lowercased()
    }

    /// `MusicDesk.app` in /Applications if that is writable, otherwise in
    /// ~/Applications (created if needed). Call off the main thread.
    static func applicationsDestination(appName: String) throws -> URL {
        let fm = FileManager.default
        for folder in [systemApplicationsFolder, userApplicationsFolder] {
            if !fm.fileExists(atPath: folder.path) {
                guard folder == userApplicationsFolder else { continue }
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                } catch {
                    UpdateLog.logger.error("~/Applications konnte nicht angelegt werden: \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }
            guard fm.isWritableFile(atPath: folder.path) else { continue }
            let target = folder.appendingPathComponent(appName, isDirectory: true)
            if fm.fileExists(atPath: target.path), !fm.isWritableFile(atPath: target.path) { continue }
            return target
        }
        throw UpdateError.notWritable(path: systemApplicationsFolder.path)
    }
}

// MARK: - Private Security.framework API

/// `SecTranslocateIsTranslocatedURL` / `SecTranslocateCreateOriginalPathForURL`
/// are exported by Security.framework but not declared in its public headers,
/// so they are looked up at run time. Missing symbols → nil (path heuristic only).
private enum TranslocationAPI {
    typealias IsTranslocatedFunction = @convention(c) (
        CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> Bool
    typealias OriginalPathFunction = @convention(c) (
        CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> Unmanaged<CFURL>?

    struct Functions {
        let isTranslocated: IsTranslocatedFunction
        let originalPath: OriginalPathFunction
    }

    static func load() -> Functions? {
        // Security is already loaded by the process; dlopen only returns a
        // handle to it. The handle is intentionally never closed.
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL) else {
            return nil
        }
        guard let isSymbol = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else {
            return nil
        }
        return Functions(
            isTranslocated: unsafeBitCast(isSymbol, to: IsTranslocatedFunction.self),
            originalPath: unsafeBitCast(originalSymbol, to: OriginalPathFunction.self)
        )
    }
}
