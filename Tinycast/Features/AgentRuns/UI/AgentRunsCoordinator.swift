import Foundation
import Observation

@MainActor
@Observable
final class AgentRunsCoordinator {
    private let monitor: AgentRunsMonitor
    private let showFailure: (String) -> Void
    @ObservationIgnored private var attachTask: Task<Void, Never>?

    init(monitor: AgentRunsMonitor, showFailure: @escaping (String) -> Void) {
        self.monitor = monitor
        self.showFailure = showFailure
    }

    var runs: [AgentRun] { monitor.runs }

    func paletteDidShow() {
        monitor.start()
    }

    func paletteDidHide() {
        monitor.stop()
    }

    func attach(_ run: AgentRun) {
        guard attachTask == nil,
            let current = monitor.runs.first(where: { $0.id == run.id }),
            let command = current.attach, !command.isEmpty
        else { return }
        attachTask = Task { [weak self] in
            defer { self?.attachTask = nil }
            do {
                try await AgentRunLauncher.attach(command: command, cwd: current.cwd)
            } catch {
                guard !Task.isCancelled else { return }
                self?.showFailure("Couldn’t open kitty: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        monitor.stop()
        attachTask?.cancel()
        attachTask = nil
    }

    isolated deinit {
        attachTask?.cancel()
    }
}
