import Foundation

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
