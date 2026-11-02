import Foundation

/// What a client may do. Caller identity decides who is asking; scopes decide what it may ask for.
enum AutomationScope: String, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case agentsRead = "agents:read"
    case contextRead = "context:read"
    case clipboardRead = "clipboard:read"
    case ui
    case exec
    case model  // FORK: workflow-server
    case selection  // FORK: core-capabilities

    var title: String {
        switch self {
        case .agentsRead: "Read agent runs and terminals"
        case .contextRead: "Read what you are doing"
        case .clipboardRead: "Read the clipboard"
        case .ui: "Show messages and ask you questions"
        case .exec: "Run commands (each needs approval)"
        case .model: String(localized: "Run model completions")  // FORK: workflow-server
        case .selection: String(localized: "Read and replace selected text")  // FORK: core-capabilities
        }
    }

    static func < (lhs: AutomationScope, rhs: AutomationScope) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
