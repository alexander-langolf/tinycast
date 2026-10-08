import Foundation
import Observation
import os

@MainActor
@Observable
final class AgentRunsMonitor {
    private(set) var runs: [AgentRun] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private static let statusPath = "LangolfVault/.agents/bin/agent-status"
    nonisolated private static let logger = Logger(subsystem: "com.tinycast", category: "AgentRuns")

    func start() {
        guard pollTask == nil else { return }
        let executable = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.statusPath)
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let nextPoll = ContinuousClock.now + .seconds(2)
                do {
                    let next = try await Self.read(executable)
                    await self?.publish(next)
                } catch {
                    guard !Task.isCancelled else { return }
                    Self.logger.error("Could not read agent status: \(error.localizedDescription)")
                }
                do {
                    try await Task.sleep(until: nextPoll, clock: .continuous)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if !runs.isEmpty { runs = [] }
    }

    isolated deinit {
        pollTask?.cancel()
    }

    private func publish(_ next: [AgentRun]) {
        guard !Task.isCancelled, next != runs else { return }
        runs = next
    }

    nonisolated private static func read(_ executable: URL) async throws -> [AgentRun] {
        let invocation = Invocation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            defer {
                invocation.cancel()
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
            try invocation.launch(process)
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else {
                throw StatusFailure(status: process.terminationStatus)
            }
            return try JSONDecoder().decode([AgentRun].self, from: data)
        } onCancel: {
            invocation.cancel()
        }
    }

    private struct StatusFailure: LocalizedError {
        let status: Int32
        var errorDescription: String? { "agent-status exited with status \(status)" }
    }

    // The lock serializes launch and cancellation, including cancellation before the process exists.
    private final class Invocation: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func launch(_ process: Process) throws {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { throw CancellationError() }
            try process.run()
            self.process = process
        }

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            if let process, process.isRunning { process.terminate() }
        }
    }
}
