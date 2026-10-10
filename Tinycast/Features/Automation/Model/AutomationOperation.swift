import Foundation

/// One entry in the registry: what it is called on the wire, who may call it, and whether a human
/// must approve each call. The router, the MCP listing and the link allowlist all read this.
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

enum AutomationOperationCatalog {
    static let paletteShow = tool(
        "palette_show", "Show palette",
        "Open the launcher with a query typed in. The query is never executed.",
        scope: .ui, linkHost: "palette",
        properties: ["query": string("Text to place in the search field.", max: 200)])
    static let hudShow = tool(
        "hud_show", "Show message",
        "Show a short message pill, labelled with who sent it.",
        scope: .ui, linkHost: "hud",
        properties: ["text": string("The message.", max: 120)], required: ["text"])
    static let questionAsk = tool(
        "question_ask", "Ask the user",
        "Ask the user a question and read the answer back from tinycast://questions. Returns an id.",
        scope: .ui,
        properties: [
            "question": string("What you need to know.", max: 500),
            "choices": .object([
                "type": .string("array"), "items": string("One answer.", max: 60),
                "minItems": .number(1), "maxItems": .number(6),
                "description": .string("Buttons the user can press.")
            ]),
            "ttl_seconds": .object([
                "type": .string("integer"), "minimum": .number(10), "maximum": .number(86_400),
                "description": .string("How long the question stays open. Default 900.")
            ])
        ],
        required: ["question", "choices"])
    static let questionAcknowledge = tool(
        "question_ack", "Acknowledge an answer",
        "Mark an answered or expired question as handled so it leaves tinycast://questions.",
        scope: .ui, properties: ["id": string("The id question_ask returned.", max: 64)],
        required: ["id"])
    static let terminalFocus = tool(
        "terminal_focus", "Focus a terminal",
        "Bring a terminal this client started (terminal_run, agent_dispatch) to the front by id.",
        scope: .ui, properties: ["id": string("Terminal instance id.", max: 64)], required: ["id"])
    static let terminalRun = tool(
        "terminal_run", "Run a command",
        "Open a terminal instance running a shell command. The user approves the exact command first.",
        scope: .exec, needsApproval: true,
        properties: [
            "command": string("The exact shell command.", max: 1_000),
            "cwd": string("Working directory; defaults to the home folder.", max: 500)
        ],
        required: ["command"])
    static let agentDispatch = tool(
        "agent_dispatch", "Start a named agent",
        "Start one of the configured agent profiles in a terminal instance. The user approves first.",
        scope: .dispatch, needsApproval: true,
        properties: [
            "agent": string("A profile name from tinycast://agent-profiles.", max: 64),
            "prompt": string("The task for the agent.", max: 1_000),
            "cwd": string("Working directory; defaults to the home folder.", max: 500)
        ],
        required: ["agent", "prompt"])

    static let agents = resource(
        "tinycast://agents", "Agent runs", "Background agent runs and their state.",
        scope: .agentsRead)
    static let terminals = resource(
        "tinycast://terminals", "Terminals", "Open terminal instances and their phase.",
        scope: .agentsRead)
    static let questions = resource(
        "tinycast://questions", "Your questions",
        "Questions this client asked, with answer, expiry and acknowledgement state.", scope: .ui)
    static let agentProfiles = resource(
        "tinycast://agent-profiles", "Agent profiles", "Names agent_dispatch accepts.",
        scope: .dispatch)
    static let context = resource(
        "tinycast://context", "Context", "The frontmost app.", scope: .contextRead)

    static let all: [AutomationOperation] = [
        paletteShow, hudShow, questionAsk, questionAcknowledge, terminalFocus, terminalRun,
        agentDispatch, agents, terminals, questions, agentProfiles, context
    ]

    static func tool(named name: String) -> AutomationOperation? {
        all.first { $0.kind == .tool && $0.name == name }
    }

    static func resource(uri: String) -> AutomationOperation? {
        all.first { $0.kind == .resource && $0.name == uri }
    }

    static func linkOperation(host: String) -> AutomationOperation? {
        all.first { $0.linkHost == host.lowercased() }
    }

    /// Everything a link may name, so an attempt at a privileged tool is refused and audited
    /// rather than falling through to another handler.
    static func isClaimedByLinks(host: String) -> Bool {
        let host = host.lowercased()
        return linkOperation(host: host) != nil || tool(named: host) != nil
    }

    static func visible(to scopes: Set<AutomationScope>) -> [AutomationOperation] {
        all.filter { scopes.contains($0.scope) }
    }

    private static func string(_ description: String, max: Int) -> JSONValue {
        .object([
            "type": .string("string"), "description": .string(description),
            "maxLength": .number(Double(max))
        ])
    }

    private static func tool(
        _ name: String, _ title: String, _ summary: String, scope: AutomationScope,
        linkHost: String? = nil, needsApproval: Bool = false,
        properties: [String: JSONValue], required: [String] = []
    ) -> AutomationOperation {
        var schema: [String: JSONValue] = [
            "type": .string("object"), "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty { schema["required"] = .array(required.map(JSONValue.string)) }
        return AutomationOperation(
            kind: .tool, name: name, title: title, summary: summary, scope: scope,
            linkHost: linkHost, needsApproval: needsApproval, inputSchema: .object(schema),
            mimeType: "application/json")
    }

    private static func resource(
        _ uri: String, _ title: String, _ summary: String, scope: AutomationScope
    ) -> AutomationOperation {
        AutomationOperation(
            kind: .resource, name: uri, title: title, summary: summary, scope: scope,
            linkHost: nil, needsApproval: false, inputSchema: nil, mimeType: "application/json")
    }
}
