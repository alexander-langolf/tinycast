import Foundation

/// One line of the audit log. Arguments are redacted before they get here.
struct AutomationAuditEvent: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case received
        case denied
        case approved
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    let request: UUID
    let at: Date
    let kind: Kind
    let transport: String
    let callerRequestID: String?
    let caller: String
    let client: UUID?
    let operation: String
    let arguments: String?
    let detail: String?

    func line(encoder: JSONEncoder = AutomationAuditEvent.makeEncoder()) throws -> Data {
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Argument values reduced to something recognisable, never the whole prompt or command.
    static func summary(of arguments: [String: JSONValue]) -> String {
        arguments.sorted { $0.key < $1.key }.map { key, value in
            let key = AutomationText.visible(key, limit: Int.max)
            return switch value {
            case .string(let text): "\(key)=\(AutomationText.redacted(text))"
            case .array(let items): "\(key)=[\(items.count) items]"
            case .object: "\(key)={…}"
            case .number(let number): "\(key)=\(number)"
            case .bool(let flag): "\(key)=\(flag)"
            case .null: "\(key)=null"
            }
        }.joined(separator: " ")
    }
}
