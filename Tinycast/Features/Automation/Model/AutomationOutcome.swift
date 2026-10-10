import Foundation

/// What the router hands back. A tool's own failure is content the model can act on; a protocol
/// error is the caller's mistake. The MCP layer maps each to its place in the envelope.
enum AutomationOutcome: Equatable, Sendable {
    case value(JSONValue)
    case toolError(String)
    case rpcError(AutomationRPCError)
}

/// One call after the transport has authenticated and parsed it.
struct AutomationCall: Sendable {
    /// Identifies this attempt in the audit log, whatever the caller's own id is.
    let request: UUID
    let caller: AutomationCaller
    let operation: AutomationOperation
    let arguments: [String: JSONValue]
    let transport: String
    /// The caller's own JSON-RPC id, kept only so the audit log can be matched to its logs.
    var callerRequestID: String?
}
