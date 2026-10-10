import Foundation

/// Who is asking, separate from what they may do: a link has an identity but no scopes at all.
struct AutomationCaller: Sendable, Equatable {
    enum Channel: String, Sendable {
        case link
        case http
    }

    let channel: Channel
    let clientID: UUID?
    let label: String
    let scopes: Set<AutomationScope>

    /// Any app or web page can open a `tinycast://` URL, so a link is never granted a scope.
    static let link = AutomationCaller(
        channel: .link, clientID: nil, label: "tinycast:// link", scopes: [])

    static func client(_ client: AutomationClient) -> AutomationCaller {
        AutomationCaller(
            channel: .http, clientID: client.id, label: client.label, scopes: client.scopes)
    }
}

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
