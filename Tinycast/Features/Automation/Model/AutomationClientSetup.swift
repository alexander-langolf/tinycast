import Foundation

/// How a coding agent registers one automation client: the line or file it needs, built from this
/// build's bridge path and the client's id. Never carries a token; the bridge reads it from the
/// Keychain itself.
enum AutomationClientSetup: String, CaseIterable, Identifiable {
    case claudeCode, codex, cursor, stdio, http

    var id: Self { self }

    var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .stdio: "Other stdio client"
        case .http: "HTTP"
        }
    }

    /// Where the snippet goes, said under it.
    var placement: String {
        switch self {
        case .claudeCode: "Run in a terminal. Add --scope user to register it for every project."
        case .codex: "Run in a terminal. Codex writes it to ~/.codex/config.toml."
        case .cursor: "Merge into ~/.cursor/mcp.json, or .cursor/mcp.json in a project."
        case .stdio: "Any MCP client that launches a stdio server: command plus arguments."
        case .http:
            "For clients that speak MCP over HTTP directly. The token is the Keychain item named "
                + "here; the bridge is safer because the token never leaves the Keychain."
        }
    }

    struct Context: Equatable {
        let bridgePath: String
        let clientID: String
        let endpointURL: String
        /// The Keychain service holding the client's token, account = client id.
        let keychainService: String
    }

    func snippet(_ context: Context) -> String {
        let arguments = ["mcp", "--stdio", "--client", context.clientID]
        switch self {
        case .claudeCode:
            return "claude mcp add tinycast -- \(Self.shellQuoted(context.bridgePath)) "
                + arguments.joined(separator: " ")
        case .codex:
            return "codex mcp add tinycast -- \(Self.shellQuoted(context.bridgePath)) "
                + arguments.joined(separator: " ")
        case .cursor:
            let server: [String: Any] = ["command": context.bridgePath, "args": arguments]
            return Self.json(["mcpServers": ["tinycast": server]])
        case .stdio:
            return Self.json(["command": context.bridgePath, "args": arguments])
        case .http:
            return """
                POST \(context.endpointURL)
                Authorization: Bearer <Keychain: \(context.keychainService) / \(context.clientID)>
                Content-Type: application/json
                Accept: application/json, text/event-stream
                MCP-Protocol-Version: \(AutomationProtocolVersion.current)
                """
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func json(_ object: [String: Any]) -> String {
        let options: JSONSerialization.WritingOptions = [
            .prettyPrinted, .sortedKeys, .withoutEscapingSlashes
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return ""
        }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
