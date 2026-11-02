import Foundation

enum ForkSelectionOperations {
    static let selectionRead = AutomationOperation(
        kind: .tool, name: "selection_read", title: "Read selected text",
        summary: "Read selected text from the target app through Accessibility, BetterTouchTool or a copy borrow.",
        scope: .selection, linkHost: nil, needsApproval: false,
        inputSchema: schema(properties: ["target": .object(["type": .string("string"), "maxLength": .number(256)])]), mimeType: "application/json")
    static let quickActionRun = AutomationOperation(
        kind: .tool, name: "quick_action_run", title: "Run a Quick Action",
        summary: "Transform selected text using the configured Quick Action model and optionally replace the selection.",
        scope: .selection, linkHost: nil, needsApproval: false,
        inputSchema: schema(properties: [
            "action": .object([
                "type": .string("string"),
                "enum": .array(BuiltInQuickAction.allCases.map { .string($0.rawValue) }),
                "description": .string("fixGrammar, rewrite, translate or summarize.")
            ]),
            "instruction": .object([
                "type": .string("string"), "maxLength": .number(16_384),
                "description": .string("Override instructions for this call. Not supported by translate.")
            ]),
            "apply": .object([
                "type": .string("boolean"), "default": .bool(false),
                "description": .string("Replace selected text with the result. Defaults to false.")
            ])
        ], required: ["action"]), mimeType: "application/json")
    static let operations = [selectionRead, quickActionRun]

    static func contains(_ operation: AutomationOperation) -> Bool {
        operation.name == "lyra_rewrite" || ForkPrimitiveOperations.contains(operation.name) || operations.contains { $0.name == operation.name }
    }

    private static func schema(properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)
        ])
    }
}
