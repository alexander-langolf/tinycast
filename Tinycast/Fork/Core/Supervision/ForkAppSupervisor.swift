import Foundation

@MainActor
final class ForkAppSupervisor {
    struct Snapshot: Sendable {
        enum State: String, Sendable { case running, launching, notRunning, gaveUp }
        let bundleID: String
        let displayName: String
        let state: State
        let lastLaunchTime: Date?
        let relaunchCount: Int
    }

    let app: ForkSupervisedApp
    private let control: any ForkAppControl
    private let now: @MainActor () -> Date
    private var policy: ForkRelaunchPolicy
    private var active = false
    private var generation = 0
    private var hasLaunched = false
    private var launchPending = false
    private var lastLaunchTime: Date?
    private var pending: Task<Void, Never>?

    init(
        app: ForkSupervisedApp, control: any ForkAppControl,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.app = app
        self.control = control
        self.now = now
        policy = app.policy
    }

    var snapshot: Snapshot {
        let state: Snapshot.State
        if policy.gaveUp { state = .gaveUp }
        else if launchPending { state = .launching }
        else if control.isRunning(bundleID: app.bundleID) { state = .running }
        else { state = .notRunning }
        return Snapshot(
            bundleID: app.bundleID, displayName: app.displayName, state: state,
            lastLaunchTime: lastLaunchTime, relaunchCount: policy.count(at: now()))
    }

    func start() {
        guard !active else { return }
        active = true
        generation += 1
        policy.reset()
        hasLaunched = control.isRunning(bundleID: app.bundleID)
        control.observeTermination(bundleID: app.bundleID) { [weak self] in self?.didTerminate() }
        pending = Task { [weak self] in _ = await self?.ensureReady() }
    }

    func stop() {
        active = false
        generation += 1
        pending?.cancel()
        pending = nil
        launchPending = false
        control.stopObservingTermination()
    }

    func didTerminate() {
        guard active else { return }
        generation += 1
        let mine = generation
        launchPending = false
        pending?.cancel()
        let span = ForkTrace.begin(.appSupervision, category: .supervision, step: .termination)
        span.end(.unavailable, fields: .init(bundleID: app.bundleID))
        pending = Task { [weak self, delay = policy.delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.active, self.generation == mine, !Task.isCancelled else { return }
            _ = await self.ensureReady()
        }
    }

    func waitForPendingWork() async { await pending?.value }

    func repair() async -> Bool {
        guard active else { return false }
        generation += 1
        pending?.cancel()
        pending = nil
        launchPending = false
        policy.reset()
        hasLaunched = control.isRunning(bundleID: app.bundleID)
        return await ensureReady()
    }

    func ensureReady(timeout: TimeInterval = 3) async -> Bool {
        guard active, !Task.isCancelled else { return false }
        guard !policy.gaveUp || control.isRunning(bundleID: app.bundleID) else { return false }
        let mine = generation
        let span = ForkTrace.begin(.appSupervision, category: .supervision, step: .readiness)
        var outcome = ForkEvent.Outcome.timeout
        defer { span.end(outcome, fields: .init(bundleID: app.bundleID)) }
        let deadline = ContinuousClock.now + .milliseconds(Int64(max(0, min(timeout, 3)) * 1_000))
        while ContinuousClock.now < deadline {
            guard active, mine == generation, !Task.isCancelled else { outcome = .cancelled; return false }
            if !control.isRunning(bundleID: app.bundleID), !launchPending {
                guard launch() else { outcome = policy.gaveUp ? .gaveUp : .failed; return false }
            }
            if control.isRunning(bundleID: app.bundleID) {
                let remaining = deadline - ContinuousClock.now
                let seconds = Double(remaining.components.seconds)
                    + Double(remaining.components.attoseconds) / 1e18
                let ready = await app.probe(min(1, max(0, seconds)))
                guard active, mine == generation, !Task.isCancelled else { outcome = .cancelled; return false }
                if ready, ContinuousClock.now <= deadline, control.isRunning(bundleID: app.bundleID) {
                    launchPending = false
                    outcome = .success
                    return true
                }
            }
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { outcome = .cancelled; return false }
        }
        launchPending = false
        return false
    }

    private func launch() -> Bool {
        let span = ForkTrace.begin(.appSupervision, category: .supervision, step: .launch)
        if hasLaunched, !policy.permit(at: now()) {
            span.end(.gaveUp, fields: .init(count: policy.count(at: now()), bundleID: app.bundleID))
            return false
        }
        hasLaunched = true
        launchPending = true
        lastLaunchTime = now()
        do {
            try control.launch(bundleID: app.bundleID)
            span.end(.started, fields: .init(count: policy.count(at: now()), bundleID: app.bundleID))
            return true
        } catch {
            launchPending = false
            span.end(.failed, fields: .init(bundleID: app.bundleID, errorCode: (error as NSError).code))
            return false
        }
    }
}
