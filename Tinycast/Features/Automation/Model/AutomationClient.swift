import Foundation

/// One authenticated bearer identity. Metadata only; its token lives in the Keychain.
struct AutomationClient: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var label: String
    var scopes: Set<AutomationScope>
    let createdAt: Date
    var expiresAt: Date?

    func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}
