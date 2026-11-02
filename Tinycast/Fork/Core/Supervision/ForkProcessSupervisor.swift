import Foundation
import Observation

@MainActor
@Observable
final class ForkProcessSupervisor {
    enum State: String, Sendable { case disabled, checking, loading, running, notRunning, failed }
    enum Ownership: String, Sendable { case none, reused, started, adopted }
    struct Snapshot: Sendable {
        let name: String
        let state: State
        let ownership: Ownership
        let pid: Int32?
    }

    let name: String
    private(set) var state = State.disabled
    private(set) var ownership = Ownership.none
    private(set) var pid: Int32?
    @ObservationIgnored private let control: any ForkProcessControl
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var active = false
    @ObservationIgnored private var pending: Task<Void, Error>?
    @ObservationIgnored private var teardown: Task<Void, Never>?

    init(name: String, control: any ForkProcessControl) {
        self.name = name
        self.control = control
    }

    var snapshot: Snapshot {
        let visible = state == .running && pid.map({ !control.isRunning($0) }) == true
            ? State.notRunning : state
        return Snapshot(name: name, state: visible, ownership: ownership, pid: pid)
    }

    func start(modelPath: String, timeout: Duration = .seconds(60)) async throws {
        if let pending { try await pending.value; try Task.checkCancellation(); return }
        generation += 1
        let mine = generation
        await teardown?.value
        try Task.checkCancellation()
        guard generation == mine else { throw CancellationError() }
        active = true
        if state == .running {
            let healthy = await control.healthy()
            try validate(mine)
            if healthy { return }
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            try await ForkTrace.run(.lyra, category: .supervision) {
                try await load(modelPath: modelPath, timeout: timeout, generation: mine)
            }
        }
        pending = task
        defer { if generation == mine { pending = nil } }
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: { task.cancel() }
    }

    func refreshHealth() async {
        let mine = generation
        guard active, state == .running else { return }
        let healthy = await control.healthy()
        guard active, generation == mine else { return }
        if !healthy { state = .notRunning }
    }

    private func load(modelPath: String, timeout: Duration, generation mine: Int) async throws {
        let span = ForkTrace.begin(.lyra, category: .supervision, step: .readiness)
        state = .checking
        do {
            if await control.healthy() {
                try validate(mine)
                let recorded = await control.recordedPID()
                try validate(mine)
                pid = recorded
                ownership = recorded == nil ? .reused : .adopted
                state = .running
                span.end(.success)
                return
            }
            try validate(mine)
            guard control.portIsFree() else { throw Failure.occupied }
            pid = try control.launch(modelPath: modelPath)
            ownership = .started
            state = .loading
            ForkTrace.begin(.lyra, category: .supervision, step: .launch).end(.started)
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                try validate(mine)
                guard let pid, control.isRunning(pid) else { throw Failure.exited }
                if await control.healthy() {
                    try validate(mine)
                    guard control.isRunning(pid) else { throw Failure.exited }
                    state = .running
                    span.end(.success)
                    return
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw Failure.timeout
        } catch {
            if generation == mine {
                if ownership == .started || ownership == .adopted, let pid { await control.stop(pid) }
                if generation == mine { pid = nil; ownership = .none; state = active ? .failed : .disabled }
            }
            span.end(error is CancellationError ? .cancelled : .failed)
            throw error
        }
    }

    func stop() async {
        if let teardown { await teardown.value; return }
        active = false
        generation += 1
        let previous = pending
        pending = nil
        previous?.cancel()
        let owned = ownership == .started || ownership == .adopted
        let previousPID = pid
        pid = nil
        ownership = .none
        state = .disabled
        let task = Task { @MainActor [control] in
            _ = await previous?.result
            if owned, let previousPID {
                await control.stop(previousPID)
                ForkTrace.begin(.lyra, category: .supervision, step: .termination).end(.success)
            }
        }
        teardown = task
        await task.value
        teardown = nil
    }

    private func validate(_ mine: Int) throws {
        try Task.checkCancellation()
        guard active, generation == mine else { throw CancellationError() }
    }

    enum Failure: Error { case occupied, exited, timeout, missingModel }
}
