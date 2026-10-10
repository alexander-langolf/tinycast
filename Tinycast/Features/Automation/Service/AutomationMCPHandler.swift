import Foundation

/// MCP method dispatch over validated calls. Serves the stateless 2026-07-28 revision and answers
/// the older handshake revisions without ever minting a session.
@MainActor
final class AutomationMCPHandler {
    private let router: AutomationRouter
    private let hub: AutomationEventHub
    private let serverVersion: String
    private static let keepAlive: Duration = .seconds(15)

    init(router: AutomationRouter, hub: AutomationEventHub, serverVersion: String) {
        self.router = router
        self.hub = hub
        self.serverVersion = serverVersion
    }

    func handle(
        _ call: AutomationMCPCall, caller: AutomationCaller, acceptsEventStream: Bool
    ) async -> AutomationHTTPResponse {
        guard let id = call.id else { return .empty(202) }
        let modern = call.era == .modern
        switch call.method {
        case "initialize":
            guard case .legacy(let version) = call.era else {
                return failure(id, .methodNotFound(call.method, status: 404), call.era)
            }
            return success(id, initializeResult(version: version), call.era)
        case "ping":
            return success(id, [:], call.era)
        case "server/discover":
            guard modern else { return failure(id, .methodNotFound(call.method), call.era) }
            return success(id, discoverResult(), call.era)
        case "tools/list":
            return success(id, toolList(for: caller), call.era)
        case "tools/call":
            return await callTool(call, id: id, caller: caller)
        case "resources/list":
            return success(id, resourceList(for: caller), call.era)
        case "resources/templates/list":
            return success(id, ["resourceTemplates": .array([])], call.era)
        case "resources/read":
            return await readResource(call, id: id, caller: caller)
        case "subscriptions/listen":
            guard modern else { return failure(id, .methodNotFound(call.method), call.era) }
            guard acceptsEventStream else {
                let error = AutomationRPCError(-32600, "Accept must include text/event-stream", 406)
                return failure(id, error, call.era)
            }
            return listen(call, id: id, caller: caller)
        default:
            return failure(
                id, .methodNotFound(call.method, status: modern ? 404 : 200), call.era)
        }
    }

    // MARK: - Results

    private func serverInfo() -> JSONValue {
        .object(["name": .string("Tinycast"), "version": .string(serverVersion)])
    }

    private func capabilities(_ era: AutomationMCPCall.Era) -> JSONValue {
        let resources: JSONValue =
            era == .modern ? .object(["subscribe": .bool(true)]) : .object([:])
        return .object(["tools": .object([:]), "resources": resources])
    }

    private static let instructions =
        "Tinycast automation. Read tinycast://agents for agent runs, ask the user with question_ask, "
        + "and expect commands and agent launches to wait for the user's approval."

    private func initializeResult(version: String) -> [String: JSONValue] {
        [
            "protocolVersion": .string(version), "capabilities": capabilities(.legacy(version: version)),
            "serverInfo": serverInfo(), "instructions": .string(Self.instructions)
        ]
    }

    private func discoverResult() -> [String: JSONValue] {
        [
            "supportedVersions": .array(AutomationProtocolVersion.supported.map(JSONValue.string)),
            "capabilities": capabilities(.modern), "instructions": .string(Self.instructions),
            "ttlMs": .number(0), "cacheScope": .string("private")
        ]
    }

    private func toolList(for caller: AutomationCaller) -> [String: JSONValue] {
        let tools = AutomationOperationCatalog.visible(to: caller.scopes).filter { $0.kind == .tool }
        return [
            "tools": .array(
                tools.map { tool in
                    .object([
                        "name": .string(tool.name), "title": .string(tool.title),
                        "description": .string(
                            tool.needsApproval
                                ? tool.summary + " Each call waits for the user to approve it."
                                : tool.summary),
                        "inputSchema": tool.inputSchema ?? .object(["type": .string("object")])
                    ])
                }),
            "ttlMs": .number(0), "cacheScope": .string("private")
        ]
    }

    private func resourceList(for caller: AutomationCaller) -> [String: JSONValue] {
        let resources = AutomationOperationCatalog.visible(to: caller.scopes).filter {
            $0.kind == .resource
        }
        return [
            "resources": .array(
                resources.map { resource in
                    .object([
                        "uri": .string(resource.name), "name": .string(resource.title),
                        "title": .string(resource.title), "description": .string(resource.summary),
                        "mimeType": .string(resource.mimeType)
                    ])
                }),
            "ttlMs": .number(0), "cacheScope": .string("private")
        ]
    }

    private func callTool(
        _ call: AutomationMCPCall, id: AutomationRPCID, caller: AutomationCaller
    ) async -> AutomationHTTPResponse {
        guard let name = call.params["name"]?.stringValue else {
            return failure(id, .invalidParams("name is required"), call.era)
        }
        let arguments = call.params["arguments"]?.objectValue ?? [:]
        guard call.params["arguments"] == nil || call.params["arguments"]?.objectValue != nil else {
            return failure(id, .invalidParams("arguments must be an object"), call.era)
        }
        guard let operation = AutomationOperationCatalog.tool(named: name) else {
            router.recordUnknown(
                name, caller: caller, arguments: arguments, transport: "mcp-http",
                callerRequestID: id.description)
            return failure(id, .invalidParams("Unknown tool: \(name)"), call.era)
        }
        let outcome = await router.route(
            AutomationCall(
                request: UUID(), caller: caller, operation: operation, arguments: arguments,
                transport: "mcp-http", callerRequestID: id.description))
        switch outcome {
        case .value(let value):
            return success(id, toolResult(value, isError: false), call.era)
        case .toolError(let message):
            return success(id, toolResult(.string(message), isError: true), call.era)
        case .rpcError(let error):
            return failure(id, error, call.era)
        }
    }

    private func toolResult(_ value: JSONValue, isError: Bool) -> [String: JSONValue] {
        let text: String
        if case .string(let message) = value {
            text = message
        } else {
            text = Self.text(of: value)
        }
        var result: [String: JSONValue] = [
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(isError)
        ]
        if !isError, case .object = value { result["structuredContent"] = value }
        return result
    }

    private func readResource(
        _ call: AutomationMCPCall, id: AutomationRPCID, caller: AutomationCaller
    ) async -> AutomationHTTPResponse {
        guard let uri = call.params["uri"]?.stringValue else {
            return failure(id, .invalidParams("uri is required"), call.era)
        }
        guard let operation = AutomationOperationCatalog.resource(uri: uri) else {
            router.recordUnknown(
                uri, caller: caller, arguments: [:], transport: "mcp-http",
                callerRequestID: id.description)
            return failure(id, .invalidParams("Resource not found"), call.era)
        }
        let outcome = await router.route(
            AutomationCall(
                request: UUID(), caller: caller, operation: operation, arguments: [:],
                transport: "mcp-http", callerRequestID: id.description))
        switch outcome {
        case .value(let value):
            let contents: JSONValue = .object([
                "uri": .string(uri), "mimeType": .string(operation.mimeType),
                "text": .string(Self.text(of: value))
            ])
            return success(id, ["contents": .array([contents])], call.era)
        case .toolError(let message):
            return failure(id, .resourceUnreadable(message), call.era)
        case .rpcError(let error):
            return failure(id, error, call.era)
        }
    }

    // MARK: - Subscriptions

    private func listen(
        _ call: AutomationMCPCall, id: AutomationRPCID, caller: AutomationCaller
    ) -> AutomationHTTPResponse {
        guard let client = caller.clientID else {
            return failure(id, .invalidParams("Subscriptions need an authenticated client"), call.era)
        }
        let requested =
            call.params["notifications"]?.objectValue?["resourceSubscriptions"]?.arrayValue?
            .compactMap(\.stringValue) ?? []
        let visible = Set(
            AutomationOperationCatalog.visible(to: caller.scopes).filter { $0.kind == .resource }
                .map(\.name))
        let accepted = Set(requested).intersection(visible)
        guard let subscription = hub.subscribe(client: client, uris: accepted) else {
            return failure(id, .internalError("Too many open subscriptions"), call.era)
        }
        let meta: JSONValue = .object([AutomationMCPCall.subscriptionKey: id.json])
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let acknowledged = AutomationRPCMessage.notification(
            method: "notifications/subscriptions/acknowledged",
            params: .object([
                "_meta": meta,
                "notifications": .object([
                    "resourceSubscriptions": .array(accepted.sorted().map(JSONValue.string))
                ])
            ]))
        continuation.yield(Self.event(acknowledged))
        let pump = Task { @MainActor in
            for await uri in subscription.updates {
                continuation.yield(
                    Self.event(
                        AutomationRPCMessage.notification(
                            method: "notifications/resources/updated",
                            params: .object(["_meta": meta, "uri": .string(uri)]))))
            }
            let done = AutomationRPCMessage.result(
                id: id, .object(["resultType": .string("complete"), "_meta": meta]))
            continuation.yield(Self.event(done))
            continuation.finish()
        }
        let keepAlive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.keepAlive)
                continuation.yield(Data(":\r\n".utf8))
            }
        }
        continuation.onTermination = { [hub] _ in
            pump.cancel()
            keepAlive.cancel()
            Task { @MainActor in hub.unsubscribe(subscription.id) }
        }
        return .init(status: 200, body: .stream(stream))
    }

    private static func event(_ message: Data) -> Data {
        var data = Data("event: message\r\ndata: ".utf8)
        data.append(message)
        data.append(Data("\r\n\r\n".utf8))
        return data
    }

    // MARK: - Envelope

    private func success(
        _ id: AutomationRPCID, _ result: [String: JSONValue], _ era: AutomationMCPCall.Era
    ) -> AutomationHTTPResponse {
        var result = result
        if era == .modern {
            result["resultType"] = .string("complete")
            var meta = result["_meta"]?.objectValue ?? [:]
            meta[AutomationMCPCall.serverInfoKey] = serverInfo()
            result["_meta"] = .object(meta)
        }
        return .json(AutomationRPCMessage.result(id: id, .object(result)))
    }

    private func failure(
        _ id: AutomationRPCID, _ error: AutomationRPCError, _ era: AutomationMCPCall.Era
    ) -> AutomationHTTPResponse {
        .json(AutomationRPCMessage.error(id: id, error), status: era == .modern ? error.httpStatus : 200)
    }

    private static func text(of value: JSONValue) -> String {
        let object = value.jsonObject
        guard JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
