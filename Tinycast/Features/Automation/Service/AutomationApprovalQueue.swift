import Foundation
import Observation

/// Human approval for privileged calls, one request at a time, each shown exactly as it will run.
/// A request waits here until it is answered, expires or its caller goes away; the last two also
/// take its dialog down if it is the one on screen.
@MainActor
@Observable
final class AutomationApprovalQueue {
    private(set) var ledger = AutomationApprovalLedger()
    @ObservationIgnored private var waiters: [UUID: CheckedContinuation<AutomationApprovalVerdict, Never>] =
        [:]
    @ObservationIgnored private var expiryTimers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var presented: AutomationApprovalPresentation?
    @ObservationIgnored private var limiters: [String: AutomationRateLimiter] = [:]
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let isBusy: () -> Bool
    @ObservationIgnored private let present: (AutomationApprovalPresentation) async -> Bool

    init(
        now: @escaping () -> Date = { Date() }, isBusy: @escaping () -> Bool,
        present: @escaping (AutomationApprovalPresentation) async -> Bool
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
                scheduleExpiry(request)
                startPump()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(request.id) }
        }
    }

    func cancel(_ id: UUID) {
        withdraw(id, .cancelled)
    }

    /// A revoked or expired client's waiting requests must not be shown or honoured.
    func cancelAll(for client: UUID) {
        for request in ledger.pending where request.clientID == client { cancel(request.id) }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        for request in ledger.pending { cancel(request.id) }
    }

    /// Settles a request nobody answered, and takes its dialog down if it is showing.
    private func withdraw(_ id: UUID, _ verdict: AutomationApprovalVerdict) {
        guard ledger.contains(id) else { return }
        ledger.remove(id)
        if presented?.request.id == id { presented?.dismiss?() }
        settle(id, verdict)
    }

    private func settle(_ id: UUID, _ verdict: AutomationApprovalVerdict) {
        expiryTimers.removeValue(forKey: id)?.cancel()
        waiters.removeValue(forKey: id)?.resume(returning: verdict)
    }

    private func scheduleExpiry(_ request: AutomationApprovalRequest) {
        let delay = max(0, request.expiresAt.timeIntervalSince(now()))
        expiryTimers[request.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.withdraw(request.id, .expired)
        }
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
            let presentation = AutomationApprovalPresentation(request: request)
            presented = presentation
            let allowed = await present(presentation)
            presented = nil
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
