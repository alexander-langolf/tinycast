import Foundation

enum AutomationEndpoint {
    static let host = "127.0.0.1"
    static let path = "/mcp"

    static func port(bundleIdentifier: String?) -> UInt16 {
        switch bundleIdentifier?.split(separator: ".").last {
        case "dev": 43312
        case "beta": 43313
        default: 43311
        }
    }

    static func url(port: UInt16) -> String { "http://\(host):\(port)\(path)" }
}
