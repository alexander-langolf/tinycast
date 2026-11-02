import Foundation

enum ForkLyraOperations {
    static let rewrite = AutomationOperation(
        kind: .tool, name: "lyra_rewrite", title: "Rewrite with Lyra",
        summary: "Rewrite selected text or the focused field, and optionally apply the completed result.",
        scope: .selection, linkHost: nil, needsApproval: false,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "mode": .object(["type": .string("string"), "description": .string("A mode name from the active Lyra policy.")]),
                "target": .object(["type": .string("string"), "enum": .array(["automatic", "selection", "field"].map(JSONValue.string)), "default": .string("automatic")]),
                "apply": .object(["type": .string("boolean"), "default": .bool(false)])
            ]),
            "required": .array([.string("mode")]), "additionalProperties": .bool(false)
        ]), mimeType: "application/json")
}
