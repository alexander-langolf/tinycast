import Foundation

struct AutomationOperation: Sendable, Equatable {
    enum Kind: Sendable {
        case tool
        case resource
    }

    let kind: Kind
    /// The tool name, or the resource URI.
    let name: String
    let title: String
    let summary: String
    let scope: AutomationScope
    /// The host of a `tinycast://` URL that may invoke it; nil means links can never reach it.
    let linkHost: String?
    let needsApproval: Bool
    let inputSchema: JSONValue?
    let mimeType: String

    /// A scope above plain UI changes who may know or do something, so it needs the audit trail.
    var isPrivileged: Bool { scope != .ui }
}
