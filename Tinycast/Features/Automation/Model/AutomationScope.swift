import Foundation

/// What a client may do. Caller identity decides who is asking; scopes decide what it may ask for.
enum AutomationScope: String, CaseIterable, Codable, Sendable, Hashable, Comparable {
    case agentsRead = "agents:read"
    case contextRead = "context:read"
    case clipboardRead = "clipboard:read"
    case ui
    case exec

    var title: String {
        switch self {
        case .agentsRead: "Read agent runs and terminals"
        case .contextRead: "Read what you are doing"
        case .clipboardRead: "Read the clipboard"
        case .ui: "Show messages and ask you questions"
        case .exec: "Run commands (each needs approval)"
        }
    }

    static func < (lhs: AutomationScope, rhs: AutomationScope) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
