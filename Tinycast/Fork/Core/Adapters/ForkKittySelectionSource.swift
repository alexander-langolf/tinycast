import AppKit
import Synchronization

@MainActor
final class ForkKittySelectionSource: ForkSelectionSource {
    static let bundleID = "net.kovidgoyal.kitty"
    let kind = ForkSelection.Kind.kitty
    private(set) var failure: Failure?
    private let execute: @MainActor (Command) async throws -> String
    private static let queue = DispatchQueue(
        label: "com.tinycast.kitty-selection", qos: .userInitiated, attributes: .concurrent)

    struct Command: Sendable {
        let executable: URL
        let arguments: [String]

        init(pid: pid_t, bundleURL: URL) {
            executable = bundleURL.appendingPathComponent("Contents/MacOS/kitten")
            arguments = ["@", "--to", "unix:/tmp/kitty.sock-\(pid)",
                         "get-text", "--match", "state:focused", "--extent", "selection"]
        }
    }

    enum Failure: Int, Error, Sendable {
        case empty = 1, unavailable, timeout, outputLimit

        var message: String {
            self == .empty ? String(localized: "Select text in kitty first")
                : String(localized: "Lyra can't read kitty's selection")
        }
    }

    /// A TUI such as Claude Code captures the mouse, so kitty holds no selection;
    /// the app copies its own selection instead, which lands on the clipboard from kitty.
    static func clipboardFallback(
        text: String?, sourceBundleID: String?, createdAt: Date, now: Date, maxAge: TimeInterval = 120
    ) -> String? {
        guard sourceBundleID == bundleID, now.timeIntervalSince(createdAt) <= maxAge,
            let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    init(execute: @escaping @MainActor (Command) async throws -> String = { try await ForkKittySelectionSource.execute($0) }) {
        self.execute = execute
    }

    func read(from app: NSRunningApplication) async -> ForkSelection? {
        await read(bundleID: app.bundleIdentifier, pid: app.processIdentifier, bundleURL: app.bundleURL)
    }

    func read(bundleID: String?, pid: pid_t, bundleURL: URL?) async -> ForkSelection? {
        failure = nil
        let span = ForkTrace.begin(.lyra, category: .selection, step: .selectionRead)
        guard bundleID == Self.bundleID, pid > 0, let bundleURL else {
            failure = .unavailable
            span.end(.unavailable, fields: .init(bundleID: bundleID, errorCode: Failure.unavailable.rawValue))
            return nil
        }
        do {
            try Task.checkCancellation()
            let text = try await execute(Command(pid: pid, bundleURL: bundleURL))
            try Task.checkCancellation()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failure = .empty
                span.end(.empty, fields: .init(length: text.count, bundleID: bundleID))
                return nil
            }
            span.end(.success, fields: .init(length: text.count, bundleID: bundleID))
            return ForkSelection(text: text, source: kind)
        } catch is CancellationError {
            span.end(.cancelled, fields: .init(bundleID: bundleID))
            return nil
        } catch {
            failure = error as? Failure ?? .unavailable
            let code = (error as? Failure)?.rawValue ?? (error as NSError).code
            span.end(failure == .timeout ? .timeout : .failed,
                     fields: .init(bundleID: bundleID, errorCode: code))
            return nil
        }
    }

    private static func execute(_ command: Command) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exit = try process.runObservingExit()
        let timedOut = Mutex(false)
        let deadline = Task.detached {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            if process.isRunning {
                timedOut.withLock { $0 = true }
                terminate(process)
            }
        }
        defer { deadline.cancel() }
        let result = await withTaskCancellationHandler {
            if Task.isCancelled { terminate(process) }
            return await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: collect(from: process, awaiting: exit, reading: output))
                }
            }
        } onCancel: {
            terminate(process)
        }
        try Task.checkCancellation()
        guard !timedOut.withLock({ $0 }) else { throw Failure.timeout }
        return try result.get()
    }

    nonisolated private static func collect(
        from process: Process, awaiting exit: ProcessExit, reading output: Pipe
    ) -> Result<String, Failure> {
        let reader = output.fileHandleForReading
        defer {
            terminate(process)
            exit.wait()
            try? reader.close()
        }
        var data = Data()
        do {
            while let chunk = try reader.read(upToCount: 4096), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= 4 * 1024 * 1024 else { return .failure(.outputLimit) }
            }
        } catch { return .failure(.unavailable) }
        exit.wait()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            return .failure(.unavailable)
        }
        return .success(text)
    }

    nonisolated private static func terminate(_ process: Process) {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
