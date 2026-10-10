import Foundation

/// Who may call what. Pure: the caller's scopes and the registry entry are the whole input.
enum AutomationPolicy {
    enum Decision: Equatable, Sendable {
        case allow
        case requireApproval
        case deny(String)
    }

    static func decide(caller: AutomationCaller, operation: AutomationOperation) -> Decision {
        if caller.channel == .link {
            guard operation.kind == .tool, operation.linkHost != nil, !operation.needsApproval else {
                return .deny("Links can only open the palette or show a message")
            }
            return .allow
        }
        guard caller.scopes.contains(operation.scope) else {
            return .deny("This client lacks the \(operation.scope.rawValue) scope")
        }
        return operation.needsApproval ? .requireApproval : .allow
    }

    static func permits(caller: AutomationCaller, operation: AutomationOperation) -> Bool {
        if case .deny = decide(caller: caller, operation: operation) { return false }
        return true
    }
}
