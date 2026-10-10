import Foundation

/// `tinycast://palette?query=…` and `tinycast://hud?text=…`: the whole link surface.
enum AutomationURL {
    struct Request: Equatable, Sendable {
        let operation: AutomationOperation
        let arguments: [String: JSONValue]
    }

    static func claims(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "tinycast", let host = url.host, !host.isEmpty else {
            return false
        }
        return AutomationOperationCatalog.isClaimedByLinks(host: host)
    }

    /// Nil only for a URL this feature does not claim; a claimed but privileged host still parses,
    /// so the policy can refuse it and the audit log can record the attempt.
    static func parse(_ url: URL) -> Request? {
        guard claims(url), let host = url.host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var arguments: [String: JSONValue] = [:]
        for item in items {
            guard let value = item.value, arguments[item.name] == nil else { continue }
            arguments[item.name] = .string(value)
        }
        guard
            let operation = AutomationOperationCatalog.linkOperation(host: host)
                ?? AutomationOperationCatalog.tool(named: host.lowercased())
        else { return nil }
        return Request(operation: operation, arguments: arguments)
    }
}
