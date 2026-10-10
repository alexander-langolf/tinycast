import Foundation
import Observation

@MainActor
@Observable
final class AutomationQuestionStore {
    static let maximumOpenPerClient = 10
    static let maximumTotal = 50
    static let defaultLifetime: TimeInterval = 900

    private(set) var questions: [AutomationQuestion] = []
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var expiry: [UUID: Task<Void, Never>] = [:]
    /// Called with the owning client whenever one of its questions changes.
    @ObservationIgnored var onChange: ((UUID) -> Void)?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    /// What the user can still act on.
    var pending: [AutomationQuestion] {
        questions.filter { $0.state == .pending && $0.expiresAt > now() }
    }

    func ask(
        client: AutomationCaller, text: String, choices: [String], lifetime: TimeInterval
    )
        -> AutomationQuestion?
    {
        guard let clientID = client.clientID else { return nil }
        prune()
        let open = questions.filter { $0.clientID == clientID && $0.state == .pending }
        guard open.count < Self.maximumOpenPerClient, questions.count < Self.maximumTotal else {
            return nil
        }
        let created = now()
        let question = AutomationQuestion(
            clientID: clientID, clientLabel: client.label, text: text, choices: choices,
            createdAt: created, expiresAt: created.addingTimeInterval(lifetime))
        questions.append(question)
        scheduleExpiry(for: question)
        onChange?(clientID)
        return question
    }

    func answer(_ id: UUID, with choice: String) {
        guard let index = questions.firstIndex(where: { $0.id == id }),
            let answered = questions[index].answering(choice, at: now())
        else { return }
        questions[index] = answered
        expiry.removeValue(forKey: id)?.cancel()
        onChange?(answered.clientID)
    }

    /// Only the asking client may acknowledge, and only once the question is answered or expired.
    func acknowledge(_ id: UUID, by client: UUID) -> Bool {
        guard let index = questions.firstIndex(where: { $0.id == id && $0.clientID == client }),
            let done = questions[index].acknowledged(at: now())
        else { return false }
        questions[index] = done
        onChange?(client)
        return true
    }

    /// This client's questions, with expiry applied, minus those it has acknowledged.
    func visible(to client: UUID) -> [AutomationQuestion] {
        questions.filter { $0.clientID == client }.map { $0.settled(at: now()) }
            .filter { $0.state != .acknowledged }
    }

    func removeAll(for client: UUID) {
        for question in questions where question.clientID == client {
            expiry.removeValue(forKey: question.id)?.cancel()
        }
        questions.removeAll { $0.clientID == client }
    }

    func stop() {
        for task in expiry.values { task.cancel() }
        expiry = [:]
        questions = []
    }

    private func scheduleExpiry(for question: AutomationQuestion) {
        let delay = max(0, question.expiresAt.timeIntervalSince(now()))
        expiry[question.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expire(question.id)
        }
    }

    private func expire(_ id: UUID) {
        expiry[id] = nil
        guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
        let settled = questions[index].settled(at: now())
        guard settled != questions[index] else { return }
        questions[index] = settled
        onChange?(settled.clientID)
    }

    /// Acknowledged and long-finished questions make room for new ones.
    private func prune() {
        let cutoff = now().addingTimeInterval(-86_400)
        questions.removeAll {
            $0.state == .acknowledged || ($0.state != .pending && $0.expiresAt < cutoff)
        }
    }
}
