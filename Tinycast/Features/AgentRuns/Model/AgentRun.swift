import Foundation

struct AgentRun: Decodable, Equatable, Identifiable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case claude, subagent, codex
    }

    let id: String
    let agent: Kind
    let name: String
    let cwd: String
    let state: String
    let startedAt: Int
    let last: String?
    let attach: String?
    /// Short model name ("Opus", a Codex model id); absent from older helpers.
    let model: String?
}
