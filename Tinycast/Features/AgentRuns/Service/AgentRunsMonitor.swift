import Foundation
import Observation
import os

@MainActor
@Observable
final class AgentRunsMonitor {
    private(set) var runs: [AgentRun] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var wantedByPalette = false
    @ObservationIgnored private var heldByAutomation = false

    private static let statusPath = "LangolfVault/.agents/bin/agent-status"
    nonisolated private static let logger = Logger(subsystem: "com.tinycast", category: "AgentRuns")

    func start() {
        wantedByPalette = true
        run()
    }

    /// Automation keeps status flowing while a client is subscribed, palette or not.
    func setAutomationHold(_ hold: Bool) {
        heldByAutomation = hold
        if hold {
            run()
        } else if !wantedByPalette {
            cancelPolling()
        }
    }

    /// One read outside the poll loop, for a client reading while nothing is polling.
    func refreshOnce() async {
        guard pollTask == nil else { return }
        let executable = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.statusPath)
        guard let next = try? await Self.read(executable) else { return }
        publish(next)
    }

    private func run() {
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
        wantedByPalette = false
        guard !heldByAutomation else { return }
        cancelPolling()
    }

    private func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
        // Keep the last snapshot: the next summon shows it at once while the first poll refreshes it.
    }

    isolated deinit {
        pollTask?.cancel()
    }

    private func publish(_ next: [AgentRun]) {
        guard !Task.isCancelled, next != runs else { return }
        runs = next
    }

    nonisolated private static func read(_ executable: URL) async throws -> [AgentRun] {
        try Task.checkCancellation()
        let result = await ShellCommandRunner.run(
            "exec \"$1\"", arguments: [executable.path], standardOutputLimit: Int.max)
        try Task.checkCancellation()
        guard result.succeeded else {
            throw StatusFailure(termination: result.termination)
        }
        return try JSONDecoder().decode([AgentRun].self, from: Data((result.standardOutput ?? "").utf8))
    }

    private struct StatusFailure: LocalizedError {
        let termination: ShellCommandTermination

        var errorDescription: String? {
            switch termination {
            case .exited(let status): "agent-status exited with status \(status)"
            case .launchFailed(let message): message
            case .stopped: "agent-status was stopped"
            }
        }
    }
}
