import Foundation
import os

@MainActor
final class ForkClaudeSessionHost {
    struct Handle: Decodable, Sendable {
        let id: String
        let sessionID: String
        let cwd: String
        /// Absent once a session is stopped (`claude agents --json --all`, 2.1.296).
        let status: String?
        let state: String?
        var transcriptPath: String?

        private enum CodingKeys: String, CodingKey {
            case id, cwd, status, state, transcriptPath
            case sessionID = "sessionId"
        }
    }

    enum Failure: LocalizedError {
        case executableMissing, commandFailed(Int32, String), missingBackgroundID
        case sessionMissing(String), transcriptMissing(String), commandTimedOut

        var errorDescription: String? {
            switch self {
            case .executableMissing: "Claude Code’s configured executable could not be found."
            case .commandFailed(let code, let message):
                message.isEmpty ? "Claude Code exited with status \(code)." : message
            case .missingBackgroundID: "Claude Code did not report a background session ID."
            case .sessionMissing(let id): "Claude Code has not listed session \(id)."
            case .transcriptMissing(let id): "Claude session \(id) has not reported its transcript path."
            case .commandTimedOut: "Claude Code’s session command timed out."
            }
        }
    }

    /// Sessions skip approvals (Sasha's choice, 2026-10-11); folder trust still applies.
    nonisolated static let bypassFlags = ["--dangerously-skip-permissions"]

    let hooks: ForkClaudeSessionHooks
    private let commandPath: @MainActor () -> String
    private var preparation: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.tinycast", category: "ClaudeSession")

    init(directory: URL, commandPath: @escaping @MainActor () -> String) {
        hooks = ForkClaudeSessionHooks(directory: directory)
        self.commandPath = commandPath
    }

    isolated deinit { preparation?.cancel() }

    func prepare() {
        preparation?.cancel()
        preparation = Task { [hooks] in
            do { try await hooks.write() } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Could not write Claude session hooks")
            }
        }
    }

    func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
    }

    func start(prompt: String, directory: URL) async throws -> Handle {
        let executable = try await resolveExecutable()
        try await hooks.write()
        let output = try await Self.run(
            executable: executable,
            arguments: ["--bg"] + Self.bypassFlags + ["--settings", hooks.settingsURL.path, "--", prompt],
            directory: directory)
        let id = try Self.backgroundID(output)
        return try await resolveHandle(id: id, executable: executable)
    }

    func lookup(id: String) async throws -> Handle? {
        let executable = try await resolveExecutable()
        guard let handle = try await handles(executable: executable).first(where: { $0.id == id }) else {
            return nil
        }
        return try await withTranscript(handle)
    }

    func sessions() async throws -> [Handle] {
        let executable = try await resolveExecutable()
        return try await handles(executable: executable)
    }

    func stop(id: String) async throws {
        let executable = try await resolveExecutable()
        _ = try await Self.run(executable: executable, arguments: ["stop", id])
    }

    func resume(sessionID: String, directory: URL) async throws -> Handle {
        let executable = try await resolveExecutable()
        try await hooks.write()
        let existing = try await handles(executable: executable).first { $0.sessionID == sessionID }
        let output = try await Self.run(
            executable: executable,
            arguments: ["--bg", "--resume", sessionID] + Self.bypassFlags
                + ["--settings", hooks.settingsURL.path],
            directory: directory)
        let id = try existing?.id ?? Self.backgroundID(output)
        let handle = try await resolveHandle(id: id, executable: executable)
        guard handle.sessionID == sessionID else {
            throw Failure.sessionMissing(sessionID)
        }
        return handle
    }

    func remove(id: String) async throws {
        let executable = try await resolveExecutable()
        _ = try await Self.run(executable: executable, arguments: ["rm", id])
    }

    func resolveExecutable() async throws -> URL {
        let path = commandPath()
        let executable = await ForkAIExecutableResolver.resolve(kind: .claude, commandPath: path)
        try Task.checkCancellation()
        guard commandPath() == path else { throw CancellationError() }
        guard let executable else { throw Failure.executableMissing }
        return executable
    }

    private func resolveHandle(id: String, executable: URL) async throws -> Handle {
        for attempt in 0..<20 {
            try Task.checkCancellation()
            do {
                if let handle = try await handles(executable: executable).first(where: { $0.id == id }) {
                    return try await withTranscript(handle)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw Failure.sessionMissing(id)
            }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(100)) }
        }
        throw Failure.sessionMissing(id)
    }

    private func handles(executable: URL) async throws -> [Handle] {
        let output = try await Self.run(
            executable: executable, arguments: ["agents", "--json", "--all"])
        try Task.checkCancellation()
        return try await Self.decodeHandles(output)
    }

    @concurrent
    private static func decodeHandles(_ output: Data) async throws -> [Handle] {
        try Task.checkCancellation()
        return try JSONDecoder().decode([Listed].self, from: output).compactMap(\.handle)
    }

    /// Interactive sessions are listed without a short `id`; skip them instead of failing the list.
    private struct Listed: Decodable {
        let handle: Handle?
        init(from decoder: Decoder) throws { handle = try? Handle(from: decoder) }
    }

    private func withTranscript(_ handle: Handle) async throws -> Handle {
        var handle = handle
        if handle.transcriptPath == nil {
            handle.transcriptPath = try await hooks.transcriptPath(sessionID: handle.sessionID)
        }
        try Task.checkCancellation()
        return handle
    }

    nonisolated private static func backgroundID(_ output: Data) throws -> String {
        let text = String(decoding: output, as: UTF8.self)
        guard let marker = text.range(of: "backgrounded"),
            let separator = text[marker.upperBound...].firstIndex(of: "·")
        else {
            throw Failure.missingBackgroundID
        }
        let suffix = text[text.index(after: separator)...].drop(while: { $0.isWhitespace })
        let id = suffix.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        guard !id.isEmpty else { throw Failure.missingBackgroundID }
        return String(id)
    }

    nonisolated static func environment(running executable: URL) -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("CLAUDE") && !$0.key.hasPrefix("ANTHROPIC")
        }
        return ExecutableLocator.environment(running: executable, inherited: inherited)
    }

    @concurrent
    private static func run(
        executable: URL, arguments: [String], directory: URL? = nil
    ) async throws -> Data {
        try Task.checkCancellation()
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "tinycast-claude-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let outputURL = scratch.appending(path: "stdout")
        let errorURL = scratch.appending(path: "stderr")
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? errors.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment(running: executable)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let exit = try process.runObservingExit()
        defer { if process.isRunning { process.terminate() } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.commandTimedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
        exit.wait()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: (try? Data(contentsOf: errorURL)) ?? Data(), as: UTF8.self)
            throw Failure.commandFailed(
                process.terminationStatus, message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Data(contentsOf: outputURL)
    }
}
