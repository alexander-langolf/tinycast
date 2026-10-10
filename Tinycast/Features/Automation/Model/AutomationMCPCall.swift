import Foundation

/// A validated MCP message: envelope, protocol era and the headers that mirror the body.
struct AutomationMCPCall: Sendable {
    enum Era: Equatable, Sendable {
        /// Stateless: every request carries its version and capabilities in `_meta`.
        case modern
        /// An `initialize` handshake revision; the server keeps no session for it.
        case legacy(version: String)
    }

    static let versionKey = "io.modelcontextprotocol/protocolVersion"
    static let capabilitiesKey = "io.modelcontextprotocol/clientCapabilities"
    static let serverInfoKey = "io.modelcontextprotocol/serverInfo"
    static let subscriptionKey = "io.modelcontextprotocol/subscriptionId"

    let id: AutomationRPCID?
    let method: String
    let params: [String: JSONValue]
    let era: Era

    var isNotification: Bool { id == nil }

    /// Headers are matched case-insensitively, so the caller passes them already lowercased.
    static func parse(
        body: Data, headers: [String: String]
    ) -> Result<AutomationMCPCall, AutomationRPCError> {
        guard let root = JSONValue(data: body) else { return .failure(.parse()) }
        guard case .object(let object) = root else {
            return .failure(.invalidRequest("Send one JSON-RPC message per request"))
        }
        guard object["jsonrpc"]?.stringValue == "2.0" else {
            return .failure(.invalidRequest("jsonrpc must be \"2.0\""))
        }
        guard let method = object["method"]?.stringValue, !method.isEmpty else {
            return .failure(.invalidRequest("A client may only send requests and notifications"))
        }
        let id: AutomationRPCID?
        switch object["id"] {
        case nil: id = nil
        case .string(let value)?: id = .string(value)
        case .number(let value)?:
            guard value == value.rounded(), abs(value) < 9e15 else {
                return .failure(.invalidRequest("id must be a string or an integer"))
            }
            id = .number(Int(value))
        default: return .failure(.invalidRequest("id must be a string or an integer"))
        }
        var params: [String: JSONValue] = [:]
        if let raw = object["params"] {
            guard case .object(let value) = raw else {
                return .failure(.invalidParams("params must be an object", status: 400))
            }
            params = value
        }
        let meta = params["_meta"]?.objectValue
        let headerVersion = headers["mcp-protocol-version"]

        if let requested = meta?[versionKey]?.stringValue {
            guard requested == AutomationProtocolVersion.current else {
                return .failure(.unsupportedVersion(requested: requested))
            }
            if id != nil, let problem = modernProblem(method, params, meta, headers, headerVersion) {
                return .failure(problem)
            }
            return .success(.init(id: id, method: method, params: params, era: .modern))
        }
        if let headerVersion, headerVersion == AutomationProtocolVersion.current {
            return .failure(.headerMismatch("The request body carries no protocol metadata"))
        }
        if method == "initialize" {
            return .success(
                .init(
                    id: id, method: method, params: params,
                    era: .legacy(
                        version: AutomationProtocolVersion.negotiatedLegacy(
                            requested: params["protocolVersion"]?.stringValue))))
        }
        let version = headerVersion ?? "2025-03-26"
        guard AutomationProtocolVersion.isLegacy(version) else {
            return .failure(.unsupportedVersion(requested: version))
        }
        return .success(.init(id: id, method: method, params: params, era: .legacy(version: version)))
    }

    private static func modernProblem(
        _ method: String, _ params: [String: JSONValue], _ meta: [String: JSONValue]?,
        _ headers: [String: String], _ headerVersion: String?
    ) -> AutomationRPCError? {
        guard headerVersion == AutomationProtocolVersion.current else {
            return .headerMismatch("MCP-Protocol-Version does not match the request body")
        }
        guard meta?[capabilitiesKey]?.objectValue != nil else {
            return .invalidParams("_meta is missing \(capabilitiesKey)", status: 400)
        }
        guard headers["mcp-method"] == method else {
            return .headerMismatch("Mcp-Method does not match the request body")
        }
        let named: String?
        switch method {
        case "tools/call", "prompts/get": named = params["name"]?.stringValue
        case "resources/read": named = params["uri"]?.stringValue
        default: return nil
        }
        guard let named, let header = headers["mcp-name"], decodeName(header) == named else {
            return .headerMismatch("Mcp-Name does not match the request body")
        }
        return nil
    }

    /// `=?base64?…?=` carries a value that is not plain header ASCII.
    static func decodeName(_ header: String) -> String? {
        guard header.hasPrefix("=?base64?"), header.hasSuffix("?=") else { return header }
        let encoded = String(header.dropFirst(9).dropLast(2))
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
