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
