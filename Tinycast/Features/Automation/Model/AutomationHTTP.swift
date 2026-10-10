import Foundation

struct AutomationHTTPHead: Sendable, Equatable {
    let method: String
    let target: String
    /// Names lowercased; a repeated name is rejected during parsing.
    let headers: [String: String]
    let contentLength: Int
    /// Offset of the first body byte in the buffer the head was parsed from.
    let bodyStart: Int
}

struct AutomationHTTPRejection: Error, Equatable, Sendable {
    let status: Int
    let reason: String
    var headers: [String: String] = [:]
}

/// Strict, bounded HTTP/1.1 request framing: only what a local JSON-RPC client needs.
enum AutomationHTTPParser {
    static let maximumHeadBytes = 16 * 1024
    static let maximumBodyBytes = 256 * 1024
    static let maximumHeaderCount = 64

    enum HeadResult: Equatable {
        case incomplete
        case head(AutomationHTTPHead)
    }

    static func parseHead(_ buffer: Data) -> Result<HeadResult, AutomationHTTPRejection> {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = buffer.range(of: terminator) else {
            if buffer.count > maximumHeadBytes {
                return .failure(.init(status: 431, reason: "Header section too large"))
            }
            return .success(.incomplete)
        }
        guard end.lowerBound <= maximumHeadBytes else {
            return .failure(.init(status: 431, reason: "Header section too large"))
        }
        guard let text = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8)
        else { return .failure(.init(status: 400, reason: "Headers are not UTF-8")) }
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2] == "HTTP/1.1", !requestLine[0].isEmpty,
            requestLine[1].hasPrefix("/")
        else { return .failure(.init(status: 400, reason: "Malformed request line")) }
        guard lines.count <= maximumHeaderCount else {
            return .failure(.init(status: 431, reason: "Too many headers"))
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                !line.hasPrefix(" "), !line.hasPrefix("\t")
            else { return .failure(.init(status: 400, reason: "Malformed header")) }
            let name = line[..<colon].lowercased()
            guard !name.contains(" "), !name.contains("\t") else {
                return .failure(.init(status: 400, reason: "Malformed header name"))
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard headers[name] == nil else {
                return .failure(.init(status: 400, reason: "Repeated header \(name)"))
            }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else {
            return .failure(.init(status: 501, reason: "Transfer-Encoding is not supported"))
        }
        var length = 0
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0, raw.allSatisfy(\.isASCII) else {
                return .failure(.init(status: 400, reason: "Invalid Content-Length"))
            }
            guard parsed <= maximumBodyBytes else {
                return .failure(.init(status: 413, reason: "Body too large"))
            }
            length = parsed
        }
        let head = AutomationHTTPHead(
            method: String(requestLine[0]), target: String(requestLine[1]), headers: headers,
            contentLength: length, bodyStart: end.upperBound - buffer.startIndex)
        return .success(.head(head))
    }
}

/// Who may even be heard: the checks that run before a body is read or a token is compared.
enum AutomationHTTPGate {
    static let path = "/mcp"

    static func check(_ head: AutomationHTTPHead, port: UInt16) -> AutomationHTTPRejection? {
        let host = head.headers["host"]?.lowercased()
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            return .init(status: 403, reason: "Host not allowed")
        }
        // Native clients send no Origin; any Origin, even null, is a browser and is refused.
        guard head.headers["origin"] == nil else {
            return .init(status: 403, reason: "Origin not allowed")
        }
        let target = head.target.split(separator: "?", maxSplits: 1).first.map(String.init)
        guard target == path else { return .init(status: 404, reason: "Not found") }
        guard head.method == "POST" else {
            return .init(status: 405, reason: "Method not allowed", headers: ["Allow": "POST"])
        }
        return nil
    }

    /// The bearer token, from the Authorization header only: never a cookie or the URL.
    static func bearer(in head: AutomationHTTPHead) -> String? {
        guard let value = head.headers["authorization"] else { return nil }
        let parts = value.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    static func contentTypeIsJSON(_ head: AutomationHTTPHead) -> Bool {
        guard let value = head.headers["content-type"]?.lowercased() else { return false }
        let media = value.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return media == "application/json"
    }

    static func acceptsEventStream(_ head: AutomationHTTPHead) -> Bool {
        let accept = head.headers["accept"]?.lowercased() ?? ""
        return accept.contains("text/event-stream") || accept.contains("*/*")
    }
}

enum AutomationHTTPBody: Sendable {
    case empty
    case json(Data)
    case stream(AsyncStream<Data>)
}

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
