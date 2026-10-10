import Foundation

enum AutomationOutcome: Equatable, Sendable {
    case value(JSONValue)
    case toolError(String)
    case rpcError(AutomationRPCError)
}
