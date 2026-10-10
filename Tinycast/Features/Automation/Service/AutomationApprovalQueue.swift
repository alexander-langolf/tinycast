import Foundation
import Observation

/// Human approval for privileged calls, one request at a time, each shown exactly as it will run.
/// A request waits here until it is answered, expires or its caller goes away.
@MainActor
@Observable
final class AutomationApprovalQueue {
    private(set) var ledger = AutomationApprovalLedger()
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<AutomationApprovalVerdict, Never>] =
        [:]
    @ObservationIgnored private var limiters: [String: AutomationRateLimiter] = [:]
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let isBusy: () -> Bool
    @ObservationIgnored private let present: (AutomationApprovalRequest) async -> Bool

    init(
        now: @escaping () -> Date = { Date() }, isBusy: @escaping () -> Bool,
        present: @escaping (AutomationApprovalRequest) async -> Bool
    ) {
        self.now = now
        self.isBusy = isBusy
        self.present = present
    }

    var pendingCount: Int { ledger.pending.count }

    func request(_ request: AutomationApprovalRequest) async -> AutomationApprovalVerdict {
        let key = request.clientID?.uuidString ?? "link"
        var limiter = limiters[key] ?? AutomationRateLimiter(capacity: 6, perSecond: 0.1)
        let admitted = limiter.take(at: now())
        limiters[key] = limiter
        guard admitted, ledger.add(request) else { return .tooMany }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[request.id] = continuation
                startPump()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(request.id) }
        }
    }

    func cancel(_ id: UUID) {
        ledger.remove(id)
        settle(id, .cancelled)
    }

    /// A revoked client's waiting requests must not be shown or honoured.
    func cancelAll(for client: UUID) {
        for request in ledger.pending where request.clientID == client { cancel(request.id) }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        for request in ledger.pending { cancel(request.id) }
    }

    private func settle(_ id: UUID, _ verdict: AutomationApprovalVerdict) {
        waiters.removeValue(forKey: id)?.resume(returning: verdict)
    }

    private func startPump() {
        guard pump == nil else { return }
        pump = Task { [weak self] in await self?.drain() }
    }

    private func drain() async {
        while !Task.isCancelled {
            let (live, expired) = ledger.next(at: now())
            for id in expired { settle(id, .expired) }
            guard let request = live else { break }
            if isBusy() {
                try? await Task.sleep(for: .milliseconds(250))
                continue
            }
            let allowed = await present(request)
            guard ledger.contains(request.id) else { continue }
            ledger.remove(request.id)
            if request.isExpired(at: now()) {
                settle(request.id, .expired)
            } else {
                settle(request.id, allowed ? .allowed : .denied)
            }
        }
        pump = nil
    }
}
