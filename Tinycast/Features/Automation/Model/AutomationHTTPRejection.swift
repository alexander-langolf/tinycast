import Foundation

struct AutomationHTTPRejection: Error, Equatable, Sendable {
    let status: Int
    let reason: String
    var headers: [String: String] = [:]
}
