import Foundation

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
    /// The read was refused or failed on Tinycast's side; the exchange itself worked, so HTTP 200.
    static func resourceUnreadable(_ message: String) -> Self { .init(-32603, message, 200) }
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
