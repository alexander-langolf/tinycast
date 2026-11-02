import Foundation

@main
@MainActor
struct ForkWorkflowTests {
    static func main() throws {
        let owner = UUID(), other = UUID()
        var now = Date(timeIntervalSince1970: 1_000)
        let handles = ForkTargetHandleStore<String>(now: { now })
        let id = handles.insert("original field", owner: owner)
        precondition(handles.resolve(id, owner: other, isCurrent: { _ in true }) == nil)
        precondition(handles.resolve(id, owner: owner, isCurrent: { $0 == "edited field" }) == nil)
        precondition(handles.resolve(id, owner: owner, isCurrent: { $0 == "original field" }) != nil)
        now.addTimeInterval(120)
        precondition(handles.resolve(id, owner: owner, isCurrent: { _ in true }) == nil)
        let consumed = handles.insert("selection", owner: owner)
        handles.remove(consumed)
        precondition(handles.resolve(consumed, owner: owner, isCurrent: { _ in true }) == nil)

        let valid: [String: JSONValue] = [
            "connection": .string("quickActions"), "instructions": .string("Preserve my voice."),
            "text": .string("A private selection"), "maxTokens": .number(2_048)
        ]
        let parsed = try ForkModelArguments(arguments: valid)
        precondition(parsed.maxTokens == 2_048 && parsed.connection == "quickActions")
        for (key, value) in [
            ("connection", JSONValue.bool(true)), ("connection", .string("")),
            ("instructions", .null), ("text", .string("  \n")),
            ("text", .string(String(repeating: "x", count: 100_001))),
            ("maxTokens", .bool(true)), ("maxTokens", .number(0)),
            ("maxTokens", .number(2.5)), ("maxTokens", .number(32_769)),
            ("unknown", .string("private"))
        ] {
            var invalid = valid
            invalid[key] = value
            do { _ = try ForkModelArguments(arguments: invalid); preconditionFailure("Invalid model arguments accepted") }
            catch is ForkModelArguments.Failure { }
        }
        for key in ["connection", "instructions", "text"] {
            var missing = valid
            missing[key] = nil
            do { _ = try ForkModelArguments(arguments: missing); preconditionFailure("Missing argument accepted") }
            catch is ForkModelArguments.Failure { }
        }
        precondition(ForkWorkflowRoute.action(URL(string: "com.tinycast.app.dev://run/rewrite")!,
                                             scheme: "com.tinycast.app.dev") == "rewrite")
        precondition(ForkWorkflowRoute.action(URL(string: "tinycast://run/lyra-fix-selection")!,
                                             scheme: "com.tinycast.app.dev") == "lyra-fix-selection")
        for link in ["other://run/rewrite", "tinycast://run/rewrite/extra", "tinycast://run/../rewrite",
                     "tinycast://run/rewrite?target=other", "tinycast://run/rewrite#fragment",
                     "tinycast://user@run/rewrite", "tinycast://run:43322/rewrite", "tinycast://run/%72ewrite"] {
            precondition(ForkWorkflowRoute.action(URL(string: link)!, scheme: "com.tinycast.app.dev") == nil)
        }
        let catalog: JSONValue = .object(["actions": .array([
            .object(["name": .string("rewrite"), "title": .string("Rewrite"), "linkSafe": .bool(true)]),
            .object(["name": .string("private-action"), "title": .string("Private"), "linkSafe": .bool(false)])
        ])])
        precondition(ForkWorkflowRoute.permits("rewrite", catalog: catalog))
        precondition(!ForkWorkflowRoute.permits("private-action", catalog: catalog))
        precondition(!ForkWorkflowRoute.permits("unknown", catalog: catalog))
        let environment = ForkWorkflowEnvironment.values(
            inherited: ["PATH": "/usr/bin", "TINYCAST_TOKEN": "old"], token: "server-secret",
            clientToken: "client-secret", tinycastPort: 43312, serverPort: 43322,
            diagnostics: "/tmp/private-diagnostics")
        precondition(environment["TINYCAST_SERVER_TOKEN"] == "server-secret")
        precondition(environment["TINYCAST_TOKEN"] == "client-secret")
        precondition(environment["TINYCAST_PORT"] == "43312")
        precondition(environment["TINYCAST_SERVER_PORT"] == "43322")
        precondition(environment["TINYCAST_DIAGNOSTICS_DIRECTORY"] == "/tmp/private-diagnostics")
        precondition(environment["PATH"] == "/usr/bin")
        let correlation = UUID()
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "model_complete", "arguments": [String: String]()]
        ]
        let request = try JSONSerialization.data(withJSONObject: payload)
        let parsedCall = try AutomationMCPCall.parse(body: request, headers: [
            "mcp-protocol-version": "2025-03-26", "x-tinycast-correlation": correlation.uuidString
        ]).get()
        precondition(parsedCall.correlationID == correlation)
        let untrustedCall = try AutomationMCPCall.parse(body: request, headers: [
            "mcp-protocol-version": "2025-03-26", "x-tinycast-correlation": "selected private text"
        ]).get()
        precondition(untrustedCall.correlationID == nil)
        precondition(ForkPrimitiveOperations.modelComplete.scope == .model)
        precondition(ForkPrimitiveOperations.operations.allSatisfy { $0.linkHost == nil && !$0.needsApproval })
        precondition(AutomationSchemaValidator.validate(arguments: valid,
            against: ForkPrimitiveOperations.modelComplete.inputSchema) == nil)
        var fractional = valid
        fractional["maxTokens"] = .number(1.5)
        precondition(AutomationSchemaValidator.validate(arguments: fractional,
            against: ForkPrimitiveOperations.modelComplete.inputSchema) != nil)

        let logDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let native = ForkEvent(time: Date(timeIntervalSince1970: 20), category: .automation,
                               operation: .workflow, correlationID: correlation, step: .end, outcome: .success)
        let server = ForkEvent(time: Date(timeIntervalSince1970: 10), category: .workflows,
                               operation: .workflow, correlationID: correlation, step: .start, outcome: .started)
        try native.line().write(to: logDirectory.appending(path: "events.jsonl"))
        try server.line().write(to: logDirectory.appending(path: "server.jsonl"))
        var reader = ForkLogReader(directory: logDirectory, filter: .init(correlationID: correlation))
        let merged = try reader.read()
        precondition(merged.count == 2 && merged[0].contains("workflows"))
        let reread = try reader.read()
        precondition(reread.isEmpty)
        try FileManager.default.moveItem(at: logDirectory.appending(path: "server.jsonl"),
                                         to: logDirectory.appending(path: "server.1.jsonl"))
        try native.line().write(to: logDirectory.appending(path: "server.jsonl"))
        let followed = try reader.read()
        precondition(followed.count == 1)
        print("PASSED: workflow handle expiry, changed-field refusal, arguments, link safety and environment")
    }
}
