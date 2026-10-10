import Foundation

enum AutomationRPCID: Equatable, Sendable {
    case string(String)
    case number(Int)

    var json: JSONValue {
        switch self {
        case .string(let value): .string(value)
        case .number(let value): .number(Double(value))
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        }
    }
}
