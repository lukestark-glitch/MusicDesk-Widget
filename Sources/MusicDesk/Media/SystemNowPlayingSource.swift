import AppKit
import Foundation
import os

// System-wide "Now Playing" (any app, incl. YouTube in Safari/Chrome) via the
// bundled mediaremote-adapter (https://github.com/ungive/mediaremote-adapter).
//
// Since macOS 15.4 apps can no longer read MediaRemote directly; the adapter
// runs its framework inside `/usr/bin/perl` (a platform binary that is still
// entitled). MusicDesk therefore talks to it only through child processes:
//
//   /usr/bin/perl <pl> <framework> <test client> stream --micros --no-artwork --debounce=50
//       long-running, one JSON object per line on stdout:
//       {"type":"data","diff":<bool>,"payload":{…}}
//       diff=false → payload is the complete state ({} = nothing playing),
//       diff=true  → merge into the last state; a `null` value removes the key.
//       Payload keys used here (with --micros):
//         title (String, always set when payload not empty), artist, album,
//         playing (Bool), processIdentifier, bundleIdentifier,
//         parentApplicationBundleIdentifier (e.g. the browser for a helper),
//         durationMicros, elapsedTimeMicros (Number, µs),
//         timestampEpochMicros (Number, µs since 1970 – elapsedTime was
//         measured at that moment), playbackRate (Number).
//   … test          exit 0 = functional, anything else = broken
//   … send <id>     2 = toggle play/pause, 4 = next, 5 = previous
//   … seek <µs>     absolute position in microseconds
//
// Threading: every Process is created, launched and read off the main thread.
// Parsed, Sendable values are handed to the main actor. The main thread never
// waits for a child process.

private let adapterLog = Logger(subsystem: "com.musicdesk.widget", category: "SystemNowPlaying")

// MARK: - Source

@MainActor
final class SystemNowPlayingSource: MediaSource {
    let kind: MediaSourceKind = .system
    private(set) var state: NowPlaying = .idle
    var onChange: ((NowPlaying) -> Void)?

    /// Result of the adapter `test` (cached), or a later downgrade when the
    /// stream keeps failing. `.checking` until `checkAvailability` finished.
    private(set) var availability: SystemSourceAvailability = .checking

    /// Optional: called on the main actor whenever `availability` changes
    /// (test finished, or the stream process died permanently). `onChange`
    /// is fired as well in that case, with the current `state`.
    var onAvailabilityChange: ((SystemSourceAvailability) -> Void)?

    static let missingAdapterReason = "Adapter fehlt im App-Bundle"

    private static let streamArguments = ["stream", "--micros", "--no-artwork", "--debounce=50"]
    private static let testTimeout: TimeInterval = 5
    private static let commandTimeout: TimeInterval = 5
    /// Give up (→ unavailable) after this many stream starts in a row that
    /// died without delivering any data.
    private static let maxConsecutiveFailures = 6
    private static let maxRestartDelay: TimeInterval = 30
    /// A stream that ran at least this long counts as healthy.
    private static let healthyRunDuration: TimeInterval = 30

    private let paths: AdapterPaths?
    private let streamSlot = StreamSlot()
    private let streamQueue = DispatchQueue(label: "com.musicdesk.widget.adapter.stream", qos: .utility)
    private let commandQueue = DispatchQueue(label: "com.musicdesk.widget.adapter.command", qos: .userInitiated)

    private var isActive = false
    private var streamGeneration = 0
    private var streamStartedAt = Date()
    private var receivedDataSinceLaunch = false
    private var consecutiveFailures = 0
    private var restartToken = 0

    private var isTesting = false
    private var pendingAvailabilityCompletions: [(SystemSourceAvailability) -> Void] = []

    /// Merged now playing dictionary as reported by the adapter.
    private var data: [String: AdapterValue] = [:]
    private var appNames: [String: String] = [:]

    init() {
        paths = AdapterPaths.locate(in: Bundle.main)
        if paths == nil {
            availability = .unavailable(reason: Self.missingAdapterReason)
            adapterLog.error("mediaremote-adapter not found in app bundle")
        }
    }

    deinit {
        streamSlot.replace(with: nil)
    }

    // MARK: Availability

    /// Runs the adapter `test` once, off the main thread (timeout 5 s).
    /// `completion` is called on the main actor; the result is cached.
    func checkAvailability(_ completion: @escaping (SystemSourceAvailability) -> Void) {
        if availability != .checking {
            completion(availability)
            return
        }
        pendingAvailabilityCompletions.append(completion)
        guard !isTesting else { return }
        guard let paths else {
            finishAvailabilityCheck(.unavailable(reason: Self.missingAdapterReason))
            return
        }
        isTesting = true
        let perl = paths.perl
        let arguments = paths.baseArguments + ["test"]
        let timeout = Self.testTimeout
        let ref = WeakRef(self)
        DispatchQueue.global(qos: .utility).async {
            let result = AdapterProcessRunner.run(executable: perl, arguments: arguments, timeout: timeout)
            hopToMain {
                ref.value?.didFinishTest(result)
            }
        }
    }

    private func didFinishTest(_ result: AdapterRunResult) {
        isTesting = false
        let outcome: SystemSourceAvailability
        switch result {
        case .exited(0):
            outcome = .available
        case .exited(let code):
            outcome = .unavailable(reason: "Adapter-Test fehlgeschlagen (Code \(code))")
        case .timedOut:
            outcome = .unavailable(reason: "Adapter-Test: Zeitüberschreitung")
        case .launchFailed:
            outcome = .unavailable(reason: "Adapter konnte nicht gestartet werden")
        }
        adapterLog.info("adapter test result: \(String(describing: result), privacy: .public)")
        finishAvailabilityCheck(outcome)
    }

    private func finishAvailabilityCheck(_ outcome: SystemSourceAvailability) {
        let changed = availability != outcome
        availability = outcome
        let completions = pendingAvailabilityCompletions
        pendingAvailabilityCompletions.removeAll()
        for completion in completions {
            completion(outcome)
        }
        if changed { notifyAvailabilityChanged() }
    }

    private func downgradeAvailability(_ outcome: SystemSourceAvailability) {
        guard availability != outcome else { return }
        availability = outcome
        notifyAvailabilityChanged()
    }

    /// MediaManager re-evaluates its source selection on `onChange`, so an
    /// availability change is reported through it too (with the current state).
    private func notifyAvailabilityChanged() {
        onAvailabilityChange?(availability)
        onChange?(state)
    }

    // MARK: MediaSource lifecycle

    func start() {
        guard !isActive else { return }
        isActive = true
        consecutiveFailures = 0
        launchStream()
    }

    func stop() {
        restartToken &+= 1
        streamGeneration &+= 1
        streamSlot.replace(with: nil)   // SIGTERM to the perl child
        guard isActive else { return }
        isActive = false
        data.removeAll()
        publish(.idle)
    }

    private func launchStream() {
        guard isActive, streamSlot.isEmpty else { return }
        guard let paths else {
            downgradeAvailability(.unavailable(reason: Self.missingAdapterReason))
            return
        }
        streamGeneration &+= 1
        let generation = streamGeneration
        let ref = WeakRef(self)
        let stream = AdapterStream(
            onMessage: { message in
                hopToMain {
                    ref.value?.handleStreamMessage(message, generation: generation)
                }
            },
            onExit: { status in
                hopToMain {
                    ref.value?.handleStreamExit(status: status, generation: generation)
                }
            }
        )
        streamSlot.replace(with: stream)
        streamStartedAt = Date()
        receivedDataSinceLaunch = false

        let perl = paths.perl
        let arguments = paths.baseArguments + Self.streamArguments
        streamQueue.async {
            stream.launch(executable: perl, arguments: arguments)
        }
    }

    private func handleStreamExit(status: Int32, generation: Int) {
        guard generation == streamGeneration, isActive else { return }
        streamSlot.replace(with: nil)
        data.removeAll()
        publish(.idle)

        let ranLong = Date().timeIntervalSince(streamStartedAt) >= Self.healthyRunDuration
        if receivedDataSinceLaunch || ranLong {
            consecutiveFailures = 0
        }
        consecutiveFailures += 1
        let failures = consecutiveFailures
        adapterLog.error("adapter stream exited with status \(status), failure #\(failures)")

        if consecutiveFailures > Self.maxConsecutiveFailures {
            downgradeAvailability(.unavailable(reason: "Adapter-Stream bricht wiederholt ab (Code \(status))"))
            return
        }
        let delay = min(Self.maxRestartDelay, pow(2, Double(consecutiveFailures - 1)))
        restartToken &+= 1
        let token = restartToken
        let ref = WeakRef(self)
        hopToMain(after: delay) {
            ref.value?.restartFired(token: token)
        }
    }

    private func restartFired(token: Int) {
        guard token == restartToken, isActive else { return }
        launchStream()
    }

    // MARK: Stream data

    private func handleStreamMessage(_ message: AdapterMessage, generation: Int) {
        guard generation == streamGeneration, isActive else { return }
        receivedDataSinceLaunch = true
        let now = Date()

        if message.isDiff {
            let wasPlaying = bool("playing") ?? false
            for (key, value) in message.payload {
                if value == .null {
                    data.removeValue(forKey: key)
                } else {
                    data[key] = value
                }
            }
            let isPlaying = bool("playing") ?? false
            let timingUpdated = message.payload["elapsedTimeMicros"] != nil
                || message.payload["timestampEpochMicros"] != nil
            if wasPlaying != isPlaying, !timingUpdated, state.hasTrack {
                // Play state flipped without fresh timing: freeze / resume at
                // the position the widget is currently showing.
                let position = state.position(at: now)
                data["elapsedTimeMicros"] = .number(position * 1_000_000)
                data["timestampEpochMicros"] = .number(now.timeIntervalSince1970 * 1_000_000)
            }
        } else {
            data = message.payload.filter { $0.value != .null }
        }
        publish(makeState(now: now))
    }

    private func makeState(now: Date) -> NowPlaying {
        guard let title = string("title"),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .idle }

        // Browser media is often reported by a helper process; the parent is
        // the real app (Safari, Chrome …) and has the proper icon/name.
        let appID = nonEmpty(string("parentApplicationBundleIdentifier"))
            ?? nonEmpty(string("bundleIdentifier"))

        var duration = (number("durationMicros") ?? 0) / 1_000_000
        if !duration.isFinite || duration < 0 { duration = 0 }

        var position: Double = 0
        var updatedAt = now
        if let elapsed = number("elapsedTimeMicros") {
            position = max(0, elapsed / 1_000_000)
            if let timestamp = number("timestampEpochMicros"), timestamp > 0 {
                updatedAt = min(Date(timeIntervalSince1970: timestamp / 1_000_000), now)
            }
        }

        var rate: Double = 1
        if let reported = number("playbackRate"), reported > 0 {
            rate = reported
        }

        return NowPlaying(
            source: .system,
            appBundleIdentifier: appID,
            appName: appID.flatMap { appName(for: $0) },
            isPlaying: bool("playing") ?? false,
            title: title,
            artist: nonEmpty(string("artist")),
            position: position,
            duration: duration,
            updatedAt: updatedAt,
            playbackRate: rate
        )
    }

    private func publish(_ newState: NowPlaying) {
        guard newState != state else { return }
        state = newState
        onChange?(newState)
    }

    private func appName(for bundleID: String) -> String? {
        if let cached = appNames[bundleID] { return cached }
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName
        if let name { appNames[bundleID] = name }
        return name
    }

    private func string(_ key: String) -> String? {
        if case .string(let value)? = data[key] { return value }
        return nil
    }

    private func number(_ key: String) -> Double? {
        switch data[key] {
        case .number(let value)?: return value.isFinite ? value : nil
        case .bool(let value)?: return value ? 1 : 0
        default: return nil
        }
    }

    private func bool(_ key: String) -> Bool? {
        switch data[key] {
        case .bool(let value)?: return value
        case .number(let value)?: return value != 0
        default: return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    // MARK: Commands

    func playPause() { runCommand(["send", "2"]) }     // kMRATogglePlayPause
    func nextTrack() { runCommand(["send", "4"]) }     // kMRANextTrack
    func previousTrack() { runCommand(["send", "5"]) } // kMRAPreviousTrack

    func seek(to seconds: Double) {
        guard state.hasTrack, state.hasDuration, seconds.isFinite else { return }
        let clamped = min(max(seconds, 0), state.duration)
        let micros = Int64((clamped * 1_000_000).rounded())
        runCommand(["seek", String(micros)])

        // Optimistic update so the progress bar does not jump back until the
        // adapter reports the new position.
        let now = Date()
        data["elapsedTimeMicros"] = .number(Double(micros))
        data["timestampEpochMicros"] = .number(now.timeIntervalSince1970 * 1_000_000)
        publish(makeState(now: now))
    }

    /// Short-lived adapter process on a serial background queue (keeps the
    /// order of commands, never blocks the main thread).
    private func runCommand(_ command: [String]) {
        guard let paths else { return }
        let perl = paths.perl
        let arguments = paths.baseArguments + command
        let timeout = Self.commandTimeout
        commandQueue.async {
            let result = AdapterProcessRunner.run(executable: perl, arguments: arguments, timeout: timeout)
            if result != .exited(0) {
                adapterLog.error("adapter command \(command.joined(separator: " "), privacy: .public) failed: \(String(describing: result), privacy: .public)")
            }
        }
    }
}

// MARK: - Main-actor hop

/// Runs `body` on the main actor (FIFO with other main-queue work).
private func hopToMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            body()
        }
    }
}

/// Runs `body` on the main actor after `delay` seconds.
private func hopToMain(after delay: TimeInterval, _ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        MainActor.assumeIsolated {
            body()
        }
    }
}

/// Weak reference that can be captured by `@Sendable` closures. `value` is
/// only read on the main actor.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - Bundle paths

private struct AdapterPaths: Sendable {
    let perl: URL
    let script: URL
    let framework: URL
    let testClient: URL

    /// Script, framework and test client – always passed as absolute paths.
    var baseArguments: [String] { [script.path, framework.path, testClient.path] }

    static func locate(in bundle: Bundle) -> AdapterPaths? {
        let contents = bundle.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let perl = URL(fileURLWithPath: "/usr/bin/perl")
        let script = contents.appendingPathComponent("Resources/mediaremote-adapter.pl")
        let framework = contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework", isDirectory: true)
        let frameworkBinary = framework.appendingPathComponent("MediaRemoteAdapter")
        let testClient = contents.appendingPathComponent("Helpers/MediaRemoteAdapterTestClient")

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.isExecutableFile(atPath: perl.path),
              fm.fileExists(atPath: script.path),
              fm.fileExists(atPath: framework.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fm.fileExists(atPath: frameworkBinary.path),
              fm.isExecutableFile(atPath: testClient.path)
        else { return nil }
        return AdapterPaths(perl: perl, script: script, framework: framework, testClient: testClient)
    }
}

// MARK: - JSON model

/// One JSON value from the adapter payload, reduced to what MusicDesk needs.
private enum AdapterValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init?(json value: Any) {
        if value is NSNull {
            self = .null
        } else if let string = value as? String {
            self = .string(string)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        } else {
            return nil   // arrays / objects are not used
        }
    }
}

/// One `{"type":"data","diff":…,"payload":{…}}` line.
private struct AdapterMessage: Sendable {
    let isDiff: Bool
    let payload: [String: AdapterValue]

    init?(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line, options: []),
              let root = object as? [String: Any],
              (root["type"] as? String) == "data",
              let rawPayload = root["payload"] as? [String: Any]
        else { return nil }
        isDiff = (root["diff"] as? Bool) ?? false
        var payload: [String: AdapterValue] = [:]
        for (key, raw) in rawPayload {
            if let value = AdapterValue(json: raw) {
                payload[key] = value
            }
        }
        self.payload = payload
    }
}

// MARK: - Short-lived processes

private enum AdapterRunResult: Sendable, Equatable, CustomStringConvertible {
    case exited(Int32)
    case timedOut
    case launchFailed(String)

    var description: String {
        switch self {
        case .exited(let code): return "exit \(code)"
        case .timedOut: return "timeout"
        case .launchFailed(let message): return "launch failed: \(message)"
        }
    }
}

private enum AdapterProcessRunner {
    /// Runs one adapter process to completion. BLOCKS the calling thread –
    /// call only from a background queue.
    static func run(executable: URL, arguments: [String], timeout: TimeInterval) -> AdapterRunResult {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .launchFailed(error.localizedDescription)
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            return .timedOut
        }
        return .exited(process.terminationStatus)
    }
}

// MARK: - Long-running stream process

/// Holds the current stream (thread safe, so `deinit` can terminate it).
private final class StreamSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AdapterStream?

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return current == nil
    }

    /// Replaces the current stream; the previous one is terminated.
    func replace(with stream: AdapterStream?) {
        lock.lock()
        let previous = current
        current = stream
        lock.unlock()
        if let previous, previous !== stream {
            previous.terminate()
        }
    }
}

/// One `stream` child process. stdout is read continuously via
/// `readabilityHandler` and split into lines; stderr is drained (pipe buffers
/// never fill up, so the child can never block on a write).
private final class AdapterStream: @unchecked Sendable {
    /// A single payload line is a few KB without artwork; anything far beyond
    /// that is garbage and gets dropped.
    private static let maxBufferedBytes = 4 * 1024 * 1024
    private static let maxStderrTail = 4 * 1024

    private let onMessage: @Sendable (AdapterMessage) -> Void
    private let onExit: @Sendable (Int32) -> Void

    private let lock = NSLock()
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var cancelled = false
    private var lineBuffer = Data()
    private var stderrTail = Data()

    init(onMessage: @escaping @Sendable (AdapterMessage) -> Void,
         onExit: @escaping @Sendable (Int32) -> Void) {
        self.onMessage = onMessage
        self.onExit = onExit
    }

    /// Call from a background queue.
    func launch(executable: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { [weak self] handle in
            self?.readStdout(handle)
        }
        stderrHandle.readabilityHandler = { [weak self] handle in
            self?.readStderr(handle)
        }
        process.terminationHandler = { [weak self] finished in
            self?.didTerminate(status: finished.terminationStatus)
        }

        lock.lock()
        guard !cancelled, self.process == nil else {
            lock.unlock()
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            return
        }
        var launchError: Error?
        do {
            try process.run()
            self.process = process
            self.stdoutHandle = stdoutHandle
            self.stderrHandle = stderrHandle
        } catch {
            launchError = error
        }
        lock.unlock()

        if let launchError {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            adapterLog.error("could not launch adapter stream: \(launchError.localizedDescription, privacy: .public)")
            onExit(-1)
        }
    }

    /// SIGTERM (the adapter stops its run loop and exits); SIGKILL after 1.5 s
    /// if it is still alive. Safe to call from any thread, idempotent.
    func terminate() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.killIfStillRunning()
        }
    }

    private func killIfStillRunning() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func readStdout(_ handle: FileHandle) {
        let chunk = handle.availableData
        if chunk.isEmpty {   // EOF
            handle.readabilityHandler = nil
            return
        }
        var lines: [Data] = []
        lock.lock()
        lineBuffer.append(chunk)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer.subdata(in: lineBuffer.startIndex..<newline)
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            if !line.isEmpty { lines.append(line) }
        }
        if lineBuffer.count > Self.maxBufferedBytes {
            lineBuffer.removeAll()
        }
        let isCancelled = cancelled
        lock.unlock()

        guard !isCancelled else { return }
        for line in lines {
            if let message = AdapterMessage(line: line) {
                onMessage(message)
            }
        }
    }

    private func readStderr(_ handle: FileHandle) {
        let chunk = handle.availableData
        if chunk.isEmpty {   // EOF
            handle.readabilityHandler = nil
            return
        }
        lock.lock()
        stderrTail.append(chunk)
        if stderrTail.count > Self.maxStderrTail {
            stderrTail = stderrTail.suffix(Self.maxStderrTail)
        }
        lock.unlock()
    }

    private func didTerminate(status: Int32) {
        lock.lock()
        let wasCancelled = cancelled
        let stderrText = String(decoding: stderrTail, as: UTF8.self)
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stderrHandle = nil
        lock.unlock()

        if !stderrText.isEmpty {
            adapterLog.info("adapter stderr: \(stderrText, privacy: .public)")
        }
        guard !wasCancelled else { return }
        onExit(status)
    }
}
