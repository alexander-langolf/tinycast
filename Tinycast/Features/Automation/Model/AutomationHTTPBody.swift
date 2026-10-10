import Foundation

enum AutomationHTTPBody: Sendable {
    case empty
    case json(Data)
    case stream(AsyncStream<Data>)
}
