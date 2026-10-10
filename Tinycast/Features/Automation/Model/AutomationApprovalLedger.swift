import Foundation

/// The queue's bookkeeping with the clock passed in: ordering, per-client bounds and expiry.
struct AutomationApprovalLedger: Sendable {
    static let maximumPending = 8
    static let maximumPendingPerClient = 3

    private(set) var pending: [AutomationApprovalRequest] = []

    /// False when the queue or the client's share of it is full.
    mutating func add(_ request: AutomationApprovalRequest) -> Bool {
        guard pending.count < Self.maximumPending else { return false }
        let mine = pending.filter { $0.clientID == request.clientID }.count
        guard mine < Self.maximumPendingPerClient else { return false }
        pending.append(request)
        return true
    }

    mutating func remove(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    func contains(_ id: UUID) -> Bool { pending.contains { $0.id == id } }

    mutating func next(at now: Date) -> (live: AutomationApprovalRequest?, expired: [UUID]) {
        let expired = pending.filter { $0.isExpired(at: now) }.map(\.id)
        pending.removeAll { $0.isExpired(at: now) }
        return (pending.first, expired)
    }
}
