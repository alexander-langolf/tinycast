import Foundation

enum AutomationURL {
    struct Request: Equatable, Sendable {
        let operation: AutomationOperation
        let arguments: [String: JSONValue]
    }

    static func claims(_ url: URL, channelScheme: String?) -> Bool {
        let schemes = ["tinycast", channelScheme?.lowercased()].compactMap(\.self)
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
            let host = url.host, !host.isEmpty
        else { return false }
        return AutomationOperationCatalog.isClaimedByLinks(host: host)
    }

    static func parse(_ url: URL, channelScheme: String?) -> Request? {
        guard claims(url, channelScheme: channelScheme), let host = url.host else { return nil }
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
