import Foundation

/// A question an agent put to the user. Owned by the client that asked; survives reconnects
/// because it lives here, not on any connection.
struct AutomationQuestion: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case pending
        case answered
        case expired
        case acknowledged
    }

    let id: UUID
    let clientID: UUID
    let clientLabel: String
    let text: String
    let choices: [String]
    let createdAt: Date
    let expiresAt: Date
    private(set) var state: State = .pending
    private(set) var answer: String?
    private(set) var answeredAt: Date?

    init(
        id: UUID = UUID(), clientID: UUID, clientLabel: String, text: String, choices: [String],
        createdAt: Date, expiresAt: Date
    ) {
        self.id = id
        self.clientID = clientID
        self.clientLabel = clientLabel
        self.text = text
        self.choices = choices
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    /// The state as of `now`: a pending question past its deadline reads as expired.
    func settled(at now: Date) -> AutomationQuestion {
        guard state == .pending, now >= expiresAt else { return self }
        var copy = self
        copy.state = .expired
        return copy
    }

    /// Nil when the question is no longer pending or the choice is not one offered.
    func answering(_ choice: String, at now: Date) -> AutomationQuestion? {
        let current = settled(at: now)
        guard current.state == .pending, choices.contains(choice) else { return nil }
        var copy = current
        copy.state = .answered
        copy.answer = choice
        copy.answeredAt = now
        return copy
    }

    /// Only a question that has reached a final state can be acknowledged.
    func acknowledged(at now: Date) -> AutomationQuestion? {
        let current = settled(at: now)
        guard current.state == .answered || current.state == .expired else { return nil }
        var copy = current
        copy.state = .acknowledged
        return copy
    }

    var json: JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id.uuidString), "question": .string(text),
            "choices": .array(choices.map(JSONValue.string)), "state": .string(state.rawValue),
            "createdAt": .string(Self.iso(createdAt)), "expiresAt": .string(Self.iso(expiresAt))
        ]
        if let answer { object["answer"] = .string(answer) }
        if let answeredAt { object["answeredAt"] = .string(Self.iso(answeredAt)) }
        return .object(object)
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
