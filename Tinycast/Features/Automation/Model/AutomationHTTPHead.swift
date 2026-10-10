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
