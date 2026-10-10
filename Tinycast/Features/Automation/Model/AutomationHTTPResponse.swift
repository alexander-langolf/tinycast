import Foundation

struct AutomationHTTPResponse: Sendable {
    let status: Int
    var headers: [String: String] = [:]
    let body: AutomationHTTPBody

    static func json(_ data: Data, status: Int = 200) -> Self {
        .init(status: status, body: .json(data))
    }

    static func empty(_ status: Int, headers: [String: String] = [:]) -> Self {
        .init(status: status, headers: headers, body: .empty)
    }

    static func rejected(_ rejection: AutomationHTTPRejection) -> Self {
        let message = AutomationRPCMessage.error(
            id: nil, AutomationRPCError(-32600, rejection.reason, rejection.status))
        return .init(status: rejection.status, headers: rejection.headers, body: .json(message))
    }

    /// Status line, security headers and framing; the body follows (or streams after) this.
    func head() -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(status))"]
        var fields = headers
        fields["Cache-Control"] = "no-store"
        fields["X-Content-Type-Options"] = "nosniff"
        fields["Connection"] = "close"
        switch body {
        case .empty:
            fields["Content-Length"] = "0"
        case .json(let data):
            fields["Content-Type"] = "application/json"
            fields["Content-Length"] = String(data.count)
        case .stream:
            fields["Content-Type"] = "text/event-stream"
            fields["X-Accel-Buffering"] = "no"
        }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): \(value)")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 408: "Request Timeout"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 429: "Too Many Requests"
        case 431: "Request Header Fields Too Large"
        case 501: "Not Implemented"
        case 504: "Gateway Timeout"
        default: "Error"
        }
    }
}
