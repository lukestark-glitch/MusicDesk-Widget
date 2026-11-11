import AppKit
import Foundation
import os

/// Result of running one AppleScript against Apple Music.
enum AppleScriptOutcome<Value: Sendable>: Sendable {
    case success(Value)
    /// Music was not running, so the script was not executed at all.
    case musicNotRunning
    /// AppleScript compile/execute error (`NSAppleScript.errorNumber`).
    case failure(code: Int, message: String)
}

/// Runs all NSAppleScript work on ONE dedicated serial background queue.
///
/// NSAppleScript is not thread safe, so every script object is created,
/// compiled, cached and executed exclusively on `queue`. Results are handed
/// back on the main actor.
final class AppleScriptRunner: @unchecked Sendable {
    static let musicBundleIdentifier = "com.apple.Music"

    private let queue = DispatchQueue(label: "com.musicdesk.widget.applescript", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.musicdesk.widget", category: "AppleScript")

    /// Compiled scripts, keyed by a caller supplied key. Only touched on `queue`.
    private var cache: [String: NSAppleScript] = [:]

    init() {}

    /// True when an instance of Apple Music is running (never launches it).
    static func isMusicRunning() -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: musicBundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// Drops all compiled scripts (e.g. after Music quit), so they get recompiled.
    func resetCache() {
        queue.async { [self] in
            self.cache.removeAll()
        }
    }

    /// Runs `source` on the script queue.
    ///
    /// - Parameters:
    ///   - cacheKey: when non-nil the compiled script is cached and reused.
    ///   - parse: converts the result descriptor; runs on the script queue.
    ///   - completion: called on the main actor.
    func run<Value: Sendable>(
        source: String,
        cacheKey: String?,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> Value,
        completion: @escaping @MainActor @Sendable (AppleScriptOutcome<Value>) -> Void
    ) {
        queue.async { [self] in
            let outcome = self.execute(source: source, cacheKey: cacheKey, parse: parse)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(outcome)
                }
            }
        }
    }

    // MARK: - Queue-only

    private func execute<Value: Sendable>(
        source: String,
        cacheKey: String?,
        parse: (NSAppleEventDescriptor) -> Value
    ) -> AppleScriptOutcome<Value> {
        dispatchPrecondition(condition: .onQueue(queue))

        // Check right before every script: never send AppleEvents that could launch Music.
        guard Self.isMusicRunning() else { return .musicNotRunning }

        let script: NSAppleScript
        if let cacheKey, let cached = cache[cacheKey] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else {
                return .failure(code: -1, message: "NSAppleScript could not be created")
            }
            var compileError: NSDictionary?
            if !created.compileAndReturnError(&compileError) {
                let (code, message) = Self.describe(compileError)
                logger.error("AppleScript compile failed (\(code, privacy: .public)): \(message, privacy: .public)")
                return .failure(code: code, message: message)
            }
            if let cacheKey {
                cache[cacheKey] = created
            }
            script = created
        }

        var executeError: NSDictionary?
        let result: NSAppleEventDescriptor? = script.executeAndReturnError(&executeError)
        if let executeError {
            let (code, message) = Self.describe(executeError)
            return .failure(code: code, message: message)
        }
        guard let result else {
            return .failure(code: -2, message: "AppleScript returned no result")
        }
        return .success(parse(result))
    }

    private static func describe(_ info: NSDictionary?) -> (Int, String) {
        guard let info else { return (-1, "unknown AppleScript error") }
        let code: Int
        if let number = info[NSAppleScript.errorNumber] as? NSNumber {
            code = number.intValue
        } else if let number = info[NSAppleScript.errorNumber] as? Int {
            code = number
        } else {
            code = -1
        }
        let message = (info[NSAppleScript.errorMessage] as? String)
            ?? (info[NSAppleScript.errorBriefMessage] as? String)
            ?? "unknown AppleScript error"
        return (code, message)
    }
}
