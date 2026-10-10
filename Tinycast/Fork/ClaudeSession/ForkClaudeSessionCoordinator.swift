import Foundation

@MainActor
final class ForkClaudeSessionCoordinator {
    private struct Connection {
        let reader: ForkClaudeSessionReader
        let writer: ForkClaudeSessionWriter
        let provider: ForkClaudeSessionProvider
    }

    private weak var core: AppCore?
    private var connections: [UUID: Connection] = [:]
    private var attachTerminals: Set<UUID> = []
    private var foreignTasks: [UUID: Task<Void, Never>] = [:]
    private var foreignGenerations: [UUID: UUID] = [:]

    init(core: AppCore) { self.core = core }

    isolated deinit {
        for task in foreignTasks.values { task.cancel() }
        for connection in connections.values {
            connection.reader.stop()
            connection.writer.stop()
        }
    }

    func provider(chatID: UUID) throws -> ForkClaudeSessionProvider? {
        guard let core, let entry = try core.forkClaudeSessionRegistry.cachedEntry(chatID: chatID)
        else { return nil }
        if let existing = connections[chatID] { return existing.provider }
        let reader = ForkClaudeSessionReader(
            chatID: chatID, entry: entry, registry: core.forkClaudeSessionRegistry,
            eventsURL: core.forkClaudeSessionHost.hooks.eventsURL)
        let writer = ForkClaudeSessionWriter(entry: entry, host: core.forkClaudeSessionHost, reader: reader)
        writer.isAttachTerminalOpen = attachTerminals.contains(chatID)
        let provider = ForkClaudeSessionProvider(reader: reader, writer: writer)
        reader.foreignTurn = { [weak self, weak reader] user, assistant in
            guard let self, let reader else { return }
            let replying = self.core?.aiChats.holder(of: chatID)?.isStreaming == true
            if self.foreignGenerations[chatID] != nil || (replying && !reader.hasQueuedChatTurn) {
                self.deferForeignTurn(chatID: chatID, user: user, assistant: assistant)
            } else {
                self.appendForeignTurn(
                    chatID: chatID, user: user, assistant: assistant, waiting: reader.hasQueuedChatTurn)
            }
        }
        reader.hasPendingForeignTurns = { [weak self] in self?.foreignGenerations[chatID] != nil }
        reader.onFailure = { [weak core] error in
            core?.aiChats.holder(of: chatID)?.report(error.localizedDescription)
        }
        connections[chatID] = Connection(reader: reader, writer: writer, provider: provider)
        reader.start()
        return provider
    }

    func setAttachTerminalOpen(_ open: Bool, chatID: UUID) {
        if open { attachTerminals.insert(chatID) } else { attachTerminals.remove(chatID) }
        connections[chatID]?.writer.isAttachTerminalOpen = open
    }

    func queuedCount(chatID: UUID) -> Int { connections[chatID]?.writer.queuedCount ?? 0 }

    func stop() {
        for task in foreignTasks.values { task.cancel() }
        foreignTasks = [:]
        foreignGenerations = [:]
        for connection in connections.values {
            connection.reader.stop()
            connection.writer.stop()
        }
        connections = [:]
    }

    private func deferForeignTurn(chatID: UUID, user: String, assistant: String) {
        let predecessor = foreignTasks[chatID]
        let generation = UUID()
        foreignGenerations[chatID] = generation
        foreignTasks[chatID] = Task { [weak self] in
            defer {
                if self?.foreignGenerations[chatID] == generation {
                    self?.foreignGenerations[chatID] = nil
                    self?.foreignTasks[chatID] = nil
                }
            }
            await withTaskCancellationHandler {
                await predecessor?.value
            } onCancel: {
                predecessor?.cancel()
            }
            while self?.core?.aiChats.holder(of: chatID)?.isStreaming == true {
                if self?.connections[chatID]?.reader.hasQueuedChatTurn == true { break }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let waiting = self?.connections[chatID]?.reader.hasQueuedChatTurn == true
            self?.appendForeignTurn(chatID: chatID, user: user, assistant: assistant, waiting: waiting)
        }
    }

    private func appendForeignTurn(chatID: UUID, user: String, assistant: String, waiting: Bool) {
        guard let core else { return }
        if let chat = core.aiChats.holder(of: chatID) {
            chat.forkAppendClaudeTurn(user: user, assistant: assistant, waiting: waiting)
            return
        }
        let session = core.chatHistory.session(id: chatID) ?? ChatSession(id: chatID)
        core.chatHistory.save(Self.appending(user: user, assistant: assistant, to: session, waiting: false))
    }

    static func appending(
        user: String, assistant: String, to session: ChatSession, waiting: Bool
    ) -> ChatSession {
        var messages = session.messages
        var additions: [ChatMessage] = []
        if !user.isEmpty { additions.append(ChatMessage(role: .user, text: user)) }
        if !assistant.isEmpty { additions.append(ChatMessage(role: .assistant, text: assistant)) }
        let index = waiting ? max(0, messages.count - 2) : messages.count
        messages.insert(contentsOf: additions, at: index)
        return ChatSession(
            id: session.id, createdAt: session.createdAt, updatedAt: Date(),
            messages: messages, model: session.model)
    }
}
