import Foundation

/// A request waiting for a human, keyed by its own id. Shown exactly as it will run.
struct AutomationApprovalRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let clientID: UUID?
    let clientLabel: String
    let operation: String
    let title: String
    /// Label and exact value, in display order.
    let details: [Detail]
    let createdAt: Date
    let expiresAt: Date

    struct Detail: Equatable, Sendable {
        let label: String
        let value: String
    }

    func isExpired(at now: Date) -> Bool { now >= expiresAt }
}

enum AutomationApprovalVerdict: Equatable, Sendable {
    case allowed
    case denied
    case expired
    case cancelled
    case tooMany
}

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

    /// The oldest request that is still live; expired ones are returned so the caller can settle them.
    mutating func next(at now: Date) -> (live: AutomationApprovalRequest?, expired: [UUID]) {
        let expired = pending.filter { $0.isExpired(at: now) }.map(\.id)
        pending.removeAll { $0.isExpired(at: now) }
        return (pending.first, expired)
    }
}
