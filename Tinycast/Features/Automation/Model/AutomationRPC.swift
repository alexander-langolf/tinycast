import Foundation

enum AutomationRPCID: Equatable, Sendable {
    case string(String)
    case number(Int)

    var json: JSONValue {
        switch self {
        case .string(let value): .string(value)
        case .number(let value): .number(Double(value))
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        }
    }
}

struct AutomationRPCError: Error, Equatable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?
    /// What the HTTP layer answers with; stdio ignores it.
    let httpStatus: Int

    static func parse(_ message: String = "Parse error") -> Self { .init(-32700, message, 400) }
    static func invalidRequest(_ message: String) -> Self { .init(-32600, message, 400) }
    static func invalidParams(_ message: String, status: Int = 200) -> Self {
        .init(-32602, message, status)
    }
    static func methodNotFound(_ method: String, status: Int = 200) -> Self {
        .init(-32601, "Method not found: \(method)", status)
    }
    static func internalError(_ message: String) -> Self { .init(-32603, message, 500) }
    static func headerMismatch(_ message: String) -> Self { .init(-32020, message, 400) }
    static func unsupportedVersion(requested: String) -> Self {
        .init(
            -32022, "Unsupported protocol version",
            400,
            data: .object([
                "supported": .array(AutomationProtocolVersion.supported.map(JSONValue.string)),
                "requested": .string(requested)
            ]))
    }

    init(_ code: Int, _ message: String, _ httpStatus: Int, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
        self.data = data
    }
}

enum AutomationRPCMessage {
    static func result(id: AutomationRPCID, _ result: JSONValue) -> Data {
        encode(["jsonrpc": .string("2.0"), "id": id.json, "result": result])
    }

    static func error(id: AutomationRPCID?, _ error: AutomationRPCError) -> Data {
        var body: [String: JSONValue] = [
            "code": .number(Double(error.code)), "message": .string(error.message)
        ]
        if let data = error.data { body["data"] = data }
        var message: [String: JSONValue] = ["jsonrpc": .string("2.0"), "error": .object(body)]
        if let id { message["id"] = id.json }
        return encode(message)
    }

    static func notification(method: String, params: JSONValue) -> Data {
        encode(["jsonrpc": .string("2.0"), "method": .string(method), "params": params])
    }

    static func encode(_ object: [String: JSONValue]) -> Data {
        let value = JSONValue.object(object).jsonObject
        return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
    }
}
