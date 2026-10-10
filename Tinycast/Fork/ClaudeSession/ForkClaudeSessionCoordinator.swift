import Foundation
import Observation

@MainActor
@Observable
final class ForkClaudeSessionCoordinator {
    private struct Connection {
        let reader: ForkClaudeSessionReader
        let writer: ForkClaudeSessionWriter
        let provider: ForkClaudeSessionProvider
    }

    @ObservationIgnored private weak var core: AppCore?
    @ObservationIgnored private var connections: [UUID: Connection] = [:]
    private var attachTerminals: Set<UUID> = []
    private var approvals: [UUID: String] = [:]
    private var busyChats: Set<UUID> = []
    private var revision = 0
    private var endedChats: Set<UUID> = []
    @ObservationIgnored private var actionTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var actionGenerations: [UUID: UUID] = [:]
    @ObservationIgnored private var terminalIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var foreignTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var foreignGenerations: [UUID: UUID] = [:]

    init(core: AppCore) { self.core = core }

    isolated deinit {
        for task in actionTasks.values { task.cancel() }
        for task in foreignTasks.values { task.cancel() }
        for connection in connections.values {
            connection.reader.stop()
            connection.writer.stop()
        }
    }

    func provider(chatID: UUID, initialPrompt: String? = nil) throws -> ForkClaudeSessionProvider? {
        guard let core, let entry = try core.forkClaudeSessionRegistry.cachedEntry(chatID: chatID)
        else { return nil }
        guard entry.ended != true, !endedChats.contains(chatID) else { throw CancellationError() }
        if let existing = connections[chatID] { return existing.provider }
        let reader = ForkClaudeSessionReader(
            chatID: chatID, entry: entry, registry: core.forkClaudeSessionRegistry,
            eventsURL: core.forkClaudeSessionHost.hooks.eventsURL)
        let writer = ForkClaudeSessionWriter(entry: entry, host: core.forkClaudeSessionHost, reader: reader)
        writer.isAttachTerminalOpen = attachTerminals.contains(chatID)
        let provider = ForkClaudeSessionProvider(reader: reader, writer: writer, initialPrompt: initialPrompt)
        reader.approvalChanged = { [weak self] tool in self?.approvals[chatID] = tool }
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
        revision += 1
        reader.start()
        return provider
    }

    func send(_ input: String, in chat: AIChatState) -> Bool? {
        guard entry(chatID: chat.session.id) != nil else { return nil }
        guard !isEnded(chatID: chat.session.id), !isBusy(chatID: chat.session.id) else { return false }
        do {
            guard let provider = try provider(chatID: chat.session.id) else { return false }
            return chat.send(input, using: provider)
        } catch {
            chat.report(error.localizedDescription)
            return false
        }
    }

    func setAttachTerminalOpen(_ open: Bool, chatID: UUID) {
        if open { attachTerminals.insert(chatID) } else { attachTerminals.remove(chatID) }
        connections[chatID]?.writer.isAttachTerminalOpen = open
    }

    func entry(chatID: UUID) -> ForkClaudeSessionRegistry.Entry? {
        _ = revision
        guard let core,
            var entry = try? core.forkClaudeSessionRegistry.cachedEntry(chatID: chatID) else {
            return nil
        }
        if endedChats.contains(chatID) { entry.ended = true }
        return entry
    }

    func approvalTool(chatID: UUID) -> String? { approvals[chatID] }
    func isEnded(chatID: UUID) -> Bool { entry(chatID: chatID)?.ended == true }
    func isBusy(chatID: UUID) -> Bool { busyChats.contains(chatID) }

    func actions(chatID: UUID) -> [PopoverMenuItem] {
        guard let entry = entry(chatID: chatID) else { return [] }
        let busy = isBusy(chatID: chatID)
        if isEnded(chatID: chatID) {
            return [PopoverMenuItem(
                title: "Resume", systemImage: "play", isLoading: busy,
                isEnabled: FileManager.default.fileExists(atPath: entry.transcriptPath)
            ) { [weak self] in self?.resume(chatID: chatID) }]
        }
        return [
            PopoverMenuItem(title: "Open in Terminal", systemImage: "terminal", isEnabled: !busy) {
                [weak self] in self?.openInTerminal(chatID: chatID)
            },
            PopoverMenuItem(
                title: "End Session", systemImage: "stop", isLoading: busy, isDestructive: true
            ) { [weak self] in self?.endSession(chatID: chatID) },
        ]
    }

    func openInTerminal(chatID: UUID) {
        guard let core, let entry = entry(chatID: chatID), !isEnded(chatID: chatID),
            !isBusy(chatID: chatID), !attachTerminals.contains(chatID) else { return }
        perform(chatID: chatID) { [weak self, weak core] in
            guard let self, let core else { throw CancellationError() }
            let executable = try await core.forkClaudeSessionHost.resolveExecutable()
            try Task.checkCancellation()
            guard let current = self.entry(chatID: chatID), current.sessionID == entry.sessionID,
                current.shortID == entry.shortID, current.ended != true else {
                throw CancellationError()
            }
            var environment = ForkClaudeSessionHost.environment(running: executable)
            environment["TERM"] = "xterm-256color"
            self.setAttachTerminalOpen(true, chatID: chatID)
            let instance = core.terminalInstances.open(
                command: executable.path + " attach " + entry.shortID, directory: entry.folder,
                executable: TerminalSession.Executable(
                    path: executable.path, arguments: ["attach", entry.shortID],
                    environment: environment),
                displayTitle: "Claude Code · " + URL(fileURLWithPath: entry.folder).lastPathComponent,
                onClose: { [weak self] in
                    self?.terminalIDs[chatID] = nil
                    self?.setAttachTerminalOpen(false, chatID: chatID)
                })
            self.terminalIDs[chatID] = instance?.id
            if instance == nil { self.setAttachTerminalOpen(false, chatID: chatID) }
        }
    }

    func endSession(chatID: UUID) {
        guard let core, let entry = entry(chatID: chatID), !isEnded(chatID: chatID),
            !isBusy(chatID: chatID) else { return }
        perform(chatID: chatID) { [weak self, weak core] in
            guard let self, let core else { throw CancellationError() }
            try await core.forkClaudeSessionHost.stop(id: entry.shortID)
            try Task.checkCancellation()
            guard self.entry(chatID: chatID)?.sessionID == entry.sessionID else {
                throw CancellationError()
            }
            self.endedChats.insert(chatID)
            self.disconnect(chatID: chatID)
            core.aiChats.holder(of: chatID)?.cancel()
            var ended = try core.forkClaudeSessionRegistry.cachedEntry(chatID: chatID) ?? entry
            ended.ended = true
            try await core.forkClaudeSessionRegistry.register(chatID: chatID, entry: ended)
            try Task.checkCancellation()
            self.revision += 1
        }
    }

    func resume(chatID: UUID) {
        guard let core, let entry = entry(chatID: chatID), isEnded(chatID: chatID),
            FileManager.default.fileExists(atPath: entry.transcriptPath),
            !isBusy(chatID: chatID) else { return }
        perform(chatID: chatID) { [weak self, weak core] in
            guard let self, let core else { throw CancellationError() }
            let handle = try await core.forkClaudeSessionHost.resume(
                sessionID: entry.sessionID, directory: URL(fileURLWithPath: entry.folder))
            try Task.checkCancellation()
            guard self.entry(chatID: chatID) == entry else { throw CancellationError() }
            guard let transcript = handle.transcriptPath else {
                throw ForkClaudeSessionHost.Failure.transcriptMissing(handle.id)
            }
            self.disconnect(chatID: chatID)
            try await core.forkClaudeSessionRegistry.register(
                chatID: chatID, entry: ForkClaudeSessionRegistry.Entry(
                    shortID: handle.id, sessionID: handle.sessionID, transcriptPath: transcript,
                    folder: entry.folder, readOffset: transcript == entry.transcriptPath ? entry.readOffset : 0,
                    ended: false))
            try Task.checkCancellation()
            self.endedChats.remove(chatID)
            self.revision += 1
            _ = try self.provider(chatID: chatID)
        }
    }

    private func perform(chatID: UUID, operation: @escaping @MainActor () async throws -> Void) {
        let generation = UUID()
        busyChats.insert(chatID)
        actionGenerations[chatID] = generation
        actionTasks[chatID] = Task { [weak self] in
            defer {
                if self?.actionGenerations[chatID] == generation {
                    self?.busyChats.remove(chatID)
                    self?.actionGenerations[chatID] = nil
                    self?.actionTasks[chatID] = nil
                }
            }
            do { try await operation() } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self?.actionGenerations[chatID] == generation else { return }
                self?.core?.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    private func disconnect(chatID: UUID) {
        foreignTasks.removeValue(forKey: chatID)?.cancel()
        foreignGenerations[chatID] = nil
        if let connection = connections.removeValue(forKey: chatID) {
            connection.reader.stop()
            connection.writer.stop()
        }
        approvals[chatID] = nil
        if let id = terminalIDs[chatID],
            let terminal = core?.terminalInstances.instances.first(where: { $0.id == id }) {
            core?.terminalInstances.close(terminal)
        }
        terminalIDs[chatID] = nil
        setAttachTerminalOpen(false, chatID: chatID)
    }

    func queuedCount(chatID: UUID) -> Int { connections[chatID]?.writer.queuedCount ?? 0 }

    func stop() {
        for task in actionTasks.values { task.cancel() }
        actionTasks = [:]
        actionGenerations = [:]
        busyChats = []
        approvals = [:]
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
