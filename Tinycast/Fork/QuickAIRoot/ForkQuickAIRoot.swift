import Foundation

@MainActor
final class ForkQuickAIRoot {
    struct Parameters: Equatable, Sendable {
        let model: String
        let webSearch: Bool
        let instructions: String
    }

    struct Root: Equatable, Sendable {
        let threadID: String
        let model: String
        let webSearch: Bool
        let instructions: String
        let startedAt: Date

        var parameters: Parameters {
            Parameters(model: model, webSearch: webSearch, instructions: instructions)
        }
    }

    enum State: Equatable, Sendable {
        case off, warming
        case ready(Root)
        case inUse(Root, chat: UUID)
        case unavailable(reason: String)
    }

    enum Event: Sendable {
        case warm(Parameters)
        case warmed(Root)
        case failed(String)
        case claim(Parameters, chat: UUID)
        case retire(ForkQuickAIRootLog.Reason)
        case unavailable(ForkQuickAIRootLog.Reason)
    }

    enum Effect: Sendable {
        case startThread(Parameters)
        case warmed(Root)
        case claimed(Root, chat: UUID)
        case retired(Root, chat: UUID?, reason: ForkQuickAIRootLog.Reason)
        case fellBack(root: Root?, chat: UUID?, reason: ForkQuickAIRootLog.Reason)
    }

    private(set) var state: State = .off
    private let settings: ForkQuickAIRootSettings
    private let log: ForkQuickAIRootLog
    private let identifiesQuickAI: @MainActor (UUID) -> Bool
    private var warmingOperation: UUID?
    private var prewarmTask: Task<Void, Never>?
    private var prewarmOperation: UUID?

    isolated deinit { prewarmTask?.cancel() }

    init(
        settings: ForkQuickAIRootSettings, log: ForkQuickAIRootLog,
        isQuickAI: @escaping @MainActor (UUID) -> Bool
    ) {
        self.settings = settings
        self.log = log
        identifiesQuickAI = isQuickAI
    }

    func isQuickAI(_ conversationID: UUID?) -> Bool {
        guard settings.warmRoot, let conversationID else { return false }
        return identifiesQuickAI(conversationID)
    }

    var canWarm: Bool {
        guard settings.warmRoot else { return false }
        switch state {
        case .off, .unavailable: return true
        default: return false
        }
    }

    func warm(
        model: String, webSearch: Bool, instructions: String,
        isCurrent: @MainActor () -> Bool = { true },
        startThread: @MainActor (Parameters) async throws -> String
    ) async {
        guard settings.warmRoot, !Task.isCancelled else { return }
        let parameters = Parameters(model: model, webSearch: webSearch, instructions: instructions)
        let effects = apply(.warm(parameters))
        guard case .startThread? = effects.first else { return }
        let operation = UUID()
        warmingOperation = operation
        do {
            let threadID = try await startThread(parameters)
            try Task.checkCancellation()
            guard warmingOperation == operation else { return }
            guard isCurrent() else {
                retire(reason: .mismatch)
                return
            }
            guard settings.warmRoot else {
                retire(reason: .disabled)
                return
            }
            warmingOperation = nil
            apply(.warmed(Root(
                threadID: threadID, model: model, webSearch: webSearch,
                instructions: instructions, startedAt: Date())))
        } catch {
            guard warmingOperation == operation else { return }
            warmingOperation = nil
            apply(.unavailable(.unavailable))
        }
    }

    func claim(
        conversationID: UUID?, model: String, webSearch: Bool, instructions: String
    ) -> Root? {
        guard isQuickAI(conversationID), let conversationID, case .ready = state else { return nil }
        apply(.claim(
            Parameters(model: model, webSearch: webSearch, instructions: instructions),
            chat: conversationID))
        guard case .inUse(let root, _) = state else { return nil }
        return root
    }

    func retire(reason: ForkQuickAIRootLog.Reason) {
        cancelPrewarm()
        warmingOperation = nil
        apply(.retire(reason))
    }

    func prewarm(_ operation: @escaping @MainActor () async -> Void) {
        guard canWarm, prewarmTask == nil else { return }
        let identity = UUID()
        prewarmOperation = identity
        prewarmTask = Task { [weak self] in
            await operation()
            guard let self, self.prewarmOperation == identity else { return }
            self.prewarmTask = nil
            self.prewarmOperation = nil
        }
    }

    func stop() {
        cancelPrewarm()
        warmingOperation = nil
    }

    func prewarmFailed() {
        guard canWarm else { return }
        log.append(.fellBack, reason: .unavailable)
        apply(.unavailable(.unavailable))
    }

    func serverUnavailable(reason: ForkQuickAIRootLog.Reason) {
        guard settings.warmRoot else { return }
        switch state {
        case .ready, .inUse, .warming:
            cancelPrewarm()
        case .off, .unavailable:
            break
        }
        warmingOperation = nil
        apply(.unavailable(reason))
    }

    private func cancelPrewarm() {
        prewarmTask?.cancel()
        prewarmTask = nil
        prewarmOperation = nil
    }

    func settingsChanged() {
        if !settings.warmRoot { retire(reason: .disabled) }
    }

    nonisolated static func reduce(state: State, event: Event) -> (state: State, effects: [Effect]) {
        switch event {
        case .warm(let parameters):
            switch state {
            case .off, .unavailable:
                return (.warming, [.startThread(parameters)])
            default:
                return (state, [])
            }
        case .warmed(let root):
            guard case .warming = state else { return (state, []) }
            return (.ready(root), [.warmed(root)])
        case .failed(let reason):
            guard case .warming = state else { return (state, []) }
            return (.unavailable(reason: reason), [])
        case .claim(let parameters, let chat):
            guard case .ready(let root) = state else { return (state, []) }
            guard root.parameters == parameters else {
                return (.off, [.retired(root, chat: nil, reason: .mismatch)])
            }
            return (.inUse(root, chat: chat), [.claimed(root, chat: chat)])
        case .unavailable(let reason):
            switch state {
            case .ready(let root):
                return (.unavailable(reason: reason.rawValue), [
                    .retired(root, chat: nil, reason: reason),
                    .fellBack(root: root, chat: nil, reason: reason)
                ])
            case .inUse(let root, let chat):
                return (.unavailable(reason: reason.rawValue), [
                    .retired(root, chat: chat, reason: reason),
                    .fellBack(root: root, chat: chat, reason: reason)
                ])
            case .warming:
                return (.unavailable(reason: reason.rawValue), [
                    .fellBack(root: nil, chat: nil, reason: reason)
                ])
            case .off, .unavailable:
                return (.unavailable(reason: reason.rawValue), [])
            }
        case .retire(let reason):
            switch state {
            case .ready(let root):
                return (.off, [.retired(root, chat: nil, reason: reason)])
            case .inUse(let root, let chat):
                return (.off, [.retired(root, chat: chat, reason: reason)])
            default:
                return (.off, [])
            }
        }
    }

    @discardableResult
    private func apply(_ event: Event) -> [Effect] {
        let transition = Self.reduce(state: state, event: event)
        state = transition.state
        for effect in transition.effects {
            switch effect {
            case .startThread:
                break
            case .warmed(let root):
                log.append(.warmed, root: root.threadID)
            case .claimed(let root, let chat):
                log.append(.claimed, root: root.threadID, chat: chat)
            case .retired(let root, let chat, let reason):
                log.append(.retired, root: root.threadID, chat: chat, reason: reason)
            case .fellBack(let root, let chat, let reason):
                log.append(.fellBack, root: root?.threadID, chat: chat, reason: reason)
            }
        }
        return transition.effects
    }
}
