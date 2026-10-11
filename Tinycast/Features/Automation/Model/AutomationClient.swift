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

extension AutomationClient {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        let grants = try container.decode([String].self, forKey: .scopes)
        scopes = Set(grants.compactMap(AutomationScope.init(rawValue:)))
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}
