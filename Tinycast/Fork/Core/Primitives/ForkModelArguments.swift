import Foundation

struct ForkModelArguments: Sendable {
    enum Failure: Error { case invalid }
    let connection: String
    let instructions: String
    let text: String
    let maxTokens: Int

    init(arguments: [String: JSONValue]) throws {
        guard Set(arguments.keys).isSubset(of: ["connection", "instructions", "text", "maxTokens"]),
            let connection = arguments["connection"]?.stringValue,
            !connection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, connection.count <= 256,
            let instructions = arguments["instructions"]?.stringValue, instructions.count <= 65_536,
            let text = arguments["text"]?.stringValue, text.count <= 100_000,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalid }
        self.connection = connection
        self.instructions = instructions
        self.text = text
        if let value = arguments["maxTokens"] {
            guard case .number(let number) = value, number.isFinite, number.rounded() == number,
                (1...32_768).contains(number) else { throw Failure.invalid }
            maxTokens = Int(number)
        } else { maxTokens = 4_096 }
    }
}
