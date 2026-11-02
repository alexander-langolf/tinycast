import Foundation

enum ForkPrimitiveOperations {
    static let modelComplete = tool("model_complete", scope: .model, properties: [
        "connection": string(256), "instructions": string(65_536), "text": string(100_000),
        "maxTokens": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(32_768)])
    ], required: ["connection", "instructions", "text"])
    static let textReplace = tool("text_replace", properties: [
        "handle": string(64), "text": string(100_000)
    ], required: ["handle", "text"])
    static let preview = tool("ui_preview", properties: [
        "handle": string(64), "title": string(120), "original": string(100_000),
        "text": string(100_000), "showsDiff": .object(["type": .string("boolean")])
    ], required: ["handle", "title", "original", "text", "showsDiff"])
    static let marker = tool("ui_marker", properties: [
        "handle": string(64), "text": string(100_000)
    ], required: ["handle", "text"])
    static let result = tool("ui_result", properties: [
        "id": string(64), "cancel": .object(["type": .string("boolean")])
    ], required: ["id"])
    static let operations = [modelComplete, textReplace, preview, marker, result]

    static func contains(_ name: String) -> Bool { operations.contains { $0.name == name } }

    private static func string(_ max: Int) -> JSONValue {
        .object(["type": .string("string"), "maxLength": .number(Double(max))])
    }

    private static func tool(
        _ name: String, scope: AutomationScope = .selection,
        properties: [String: JSONValue], required: [String]
    ) -> AutomationOperation {
        AutomationOperation(
            kind: .tool, name: name, title: name,
            summary: "Native workflow primitive. Target and interaction IDs belong to the authenticated client.",
            scope: scope, linkHost: nil, needsApproval: false,
            inputSchema: .object([
                "type": .string("object"), "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)
            ]), mimeType: "application/json")
    }
}
