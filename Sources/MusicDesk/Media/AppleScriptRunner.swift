import AppKit
import Foundation
import os

/// Result of running one AppleScript against a player app.
enum AppleScriptOutcome<Value: Sendable>: Sendable {
    case success(Value)
    /// The target app was not running, so the script was not executed at all.
    case appNotRunning
    /// AppleScript compile/execute error (`NSAppleScript.errorNumber`).
    case failure(code: Int, message: String)
}

/// Runs all NSAppleScript work on ONE dedicated serial background queue.
///
/// NSAppleScript is not thread safe, so every script object is created,
/// compiled, cached and executed exclusively on `queue`. All sources share
/// `AppleScriptRunner.shared`, so scripts for Apple Music and Spotify never
/// run concurrently. Results are handed back on the main actor.
final class AppleScriptRunner: @unchecked Sendable {
    /// Shared runner (one serial queue for the whole app).
    static let shared = AppleScriptRunner()

    private let queue = DispatchQueue(label: "com.musicdesk.widget.applescript", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.musicdesk.widget", category: "AppleScript")

    /// Compiled scripts per bundle id, keyed by a caller supplied key.
    /// Only touched on `queue`.
    private var cache: [String: [String: NSAppleScript]] = [:]

    init() {}

    /// True when an instance of the app with `bundleIdentifier` is running
    /// (never launches it). Safe to call from any thread.
    static func isRunning(bundleIdentifier: String) -> Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// Drops all compiled scripts for one app (e.g. after it quit), so they
    /// get recompiled against the next instance.
    func resetCache(bundleIdentifier: String) {
        queue.async { [self] in
            self.cache[bundleIdentifier] = nil
        }
    }

    /// Runs `source` on the script queue – but only if the app with
    /// `bundleIdentifier` is running at that moment.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: the app the script talks to; checked right before execution.
    ///   - cacheKey: when non-nil the compiled script is cached and reused.
    ///   - parse: converts the result descriptor; runs on the script queue.
    ///   - completion: called on the main actor.
    func run<Value: Sendable>(
        bundleIdentifier: String,
        source: String,
        cacheKey: String?,
        parse: @escaping @Sendable (NSAppleEventDescriptor) -> Value,
        completion: @escaping @MainActor @Sendable (AppleScriptOutcome<Value>) -> Void
    ) {
        queue.async { [self] in
            let outcome = self.execute(
                bundleIdentifier: bundleIdentifier,
                source: source,
                cacheKey: cacheKey,
                parse: parse
            )
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(outcome)
                }
            }
        }
    }

    // MARK: - Queue-only

    private func execute<Value: Sendable>(
        bundleIdentifier: String,
        source: String,
        cacheKey: String?,
        parse: (NSAppleEventDescriptor) -> Value
    ) -> AppleScriptOutcome<Value> {
        dispatchPrecondition(condition: .onQueue(queue))

        // Check right before every script: never send AppleEvents that could launch the app.
        guard Self.isRunning(bundleIdentifier: bundleIdentifier) else { return .appNotRunning }

        let script: NSAppleScript
        if let cacheKey, let cached = cache[bundleIdentifier]?[cacheKey] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else {
                return .failure(code: -1, message: "NSAppleScript could not be created")
            }
            var compileError: NSDictionary?
            if !created.compileAndReturnError(&compileError) {
                let (code, message) = Self.describe(compileError)
                logger.error("AppleScript compile failed for \(bundleIdentifier, privacy: .public) (\(code, privacy: .public)): \(message, privacy: .public)")
                return .failure(code: code, message: message)
            }
            if let cacheKey {
                cache[bundleIdentifier, default: [:]][cacheKey] = created
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
