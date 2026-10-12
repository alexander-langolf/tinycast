import Foundation
import Observation
import os

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
    @ObservationIgnored private var reconciliationTask: Task<Void, Never>?
    @ObservationIgnored private var reconciliationGeneration: UUID?
    @ObservationIgnored private var lifecycleExcludedChats: Set<UUID> = []
    @ObservationIgnored private var deletionTask: Task<Void, Never>?
    @ObservationIgnored private var deletionGeneration: UUID?
    private static let logger = Logger(subsystem: "com.tinycast", category: "ClaudeSessionLifecycle")

    init(core: AppCore) { self.core = core }

    isolated deinit {
        reconciliationTask?.cancel()
        deletionTask?.cancel()
        for task in actionTasks.values { task.cancel() }
        for task in foreignTasks.values { task.cancel() }
        for connection in connections.values {
            connection.reader.stop()
            connection.writer.stop()
        }
    }

    func start() {
        guard let core, reconciliationTask == nil else { return }
        core.aiChats.forkClaudeSessionDeletion = { [weak self, weak core] ids, preservingPinned in
            self?.deleteChats(chatIDs: ids, preservingPinned: preservingPinned) { [weak core] ready in
                for id in ready { core?.aiChats.delete(id: id) }
            } ?? false
        }
        let generation = UUID()
        reconciliationGeneration = generation
        reconciliationTask = Task { [weak self, weak core] in
            guard let self, let core else { return }
            defer {
                if self.reconciliationGeneration == generation {
                    self.reconciliationTask = nil
                    self.reconciliationGeneration = nil
                    self.lifecycleExcludedChats = []
                }
            }
            do {
                let entries = try await core.forkClaudeSessionRegistry.entries()
                try Task.checkCancellation()
                guard !entries.isEmpty else { return }
                let sessions = try await core.forkClaudeSessionHost.sessions()
                try Task.checkCancellation()
                for (chatID, entry) in entries {
                    guard !Task.isCancelled, self.reconciliationGeneration == generation else { return }
                    while self.isBusy(chatID: chatID), !self.lifecycleExcludedChats.contains(chatID) {
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    let session = sessions.first {
                        $0.id == entry.shortID && $0.sessionID == entry.sessionID
                    }
                    let live =
                        session.map {
                            $0.status.map { !["stopped", "gone"].contains($0.lowercased()) } ?? false
                        } ?? false
                    do {
                        try await self.reconcile(chatID: chatID, expected: entry, live: live)
                    } catch is CancellationError {
                        if Task.isCancelled { return }
                    } catch {
                        Self.logger.error("Could not reconnect a registered Claude session")
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Could not check Claude sessions at launch")
            }
        }
    }

    private func reconcile(
        chatID: UUID, expected: ForkClaudeSessionRegistry.Entry, live: Bool
    ) async throws {
        guard let core, !lifecycleExcludedChats.contains(chatID), !isBusy(chatID: chatID),
            connections[chatID] == nil || !live,
            let current = try core.forkClaudeSessionRegistry.cachedEntry(chatID: chatID),
            current.matchesSession(expected), current.ended == expected.ended
        else { return }
        busyChats.insert(chatID)
        defer { busyChats.remove(chatID) }
        let updated = try await core.forkClaudeSessionRegistry.updateEnded(
            chatID: chatID, expected: expected, ended: !live)
        try Task.checkCancellation()
        guard updated, !lifecycleExcludedChats.contains(chatID) else { return }
        if live {
            endedChats.remove(chatID)
            revision += 1
            _ = try provider(chatID: chatID)
            connections[chatID]?.reader.onFailure = { _ in
                Self.logger.error("Could not read a reconnected Claude session")
            }
        } else {
            endedChats.insert(chatID)
            disconnect(chatID: chatID)
            core.aiChats.holder(of: chatID)?.cancel()
            revision += 1
        }
    }

    private func deleteChats(
        chatIDs: [UUID], preservingPinned: Bool,
        completion: @escaping @MainActor ([UUID]) -> Void
    ) -> Bool {
        guard let core else { return false }
        let ids = chatIDs.filter {
            !preservingPinned || core.chatHistory.conversation(id: $0)?.isPinned != true
        }
        let registered: [UUID: ForkClaudeSessionRegistry.Entry]
        do {
            var entries: [UUID: ForkClaudeSessionRegistry.Entry] = [:]
            for id in ids {
                if let entry = try core.forkClaudeSessionRegistry.cachedEntry(chatID: id) {
                    entries[id] = entry
                }
            }
            registered = entries
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return true
        }
        guard !registered.isEmpty else { return false }
        guard deletionTask == nil, !ids.contains(where: { isBusy(chatID: $0) }) else { return true }
        let generation = UUID()
        deletionGeneration = generation
        for id in ids {
            busyChats.insert(id)
        }
        deletionTask = Task { [weak self, weak core] in
            guard let self, let core else { return }
            defer {
                if self.deletionGeneration == generation {
                    for id in ids { self.busyChats.remove(id) }
                    self.deletionTask = nil
                    self.deletionGeneration = nil
                }
            }
            let multiple = registered.count > 1
            let choice = await core.choose(
                title: multiple ? "Stop Claude sessions too?" : "Stop the Claude session too?",
                message: multiple
                    ? "Delete these chats and stop and remove their Claude sessions, or leave the sessions running."
                    : "Delete this chat and stop and remove its Claude session, or leave the session running.",
                symbol: "terminal",
                options: [
                    DialogAction(
                        title: multiple ? "Delete and Stop Sessions" : "Delete and Stop Session",
                        role: .destructive),
                    DialogAction(title: "Delete Chat\(ids.count > 1 ? "s" : "") Only", role: .destructive),
                    DialogAction(title: "Cancel", role: .cancel)
                ], defaultIndex: 0)
            guard !Task.isCancelled, self.deletionGeneration == generation, choice == 0 || choice == 1
            else { return }
            if self.reconciliationGeneration != nil {
                for id in ids { self.lifecycleExcludedChats.insert(id) }
            }
            for id in ids {
                guard !Task.isCancelled, self.deletionGeneration == generation else { return }
                if preservingPinned, core.chatHistory.conversation(id: id)?.isPinned == true { continue }
                do {
                    let current = try core.forkClaudeSessionRegistry.cachedEntry(chatID: id)
                    if let expected = registered[id] {
                        guard current?.matchesSession(expected) == true else { continue }
                    } else if current != nil {
                        continue
                    }
                    if let entry = current {
                        self.disconnect(chatID: id)
                        core.aiChats.holder(of: id)?.cancel()
                        if choice == 0 {
                            try await core.forkClaudeSessionHost.stop(id: entry.shortID)
                            try Task.checkCancellation()
                            guard let stopped = try core.forkClaudeSessionRegistry.cachedEntry(chatID: id),
                                stopped.matchesSession(entry)
                            else { continue }
                            self.endedChats.insert(id)
                            _ = try await core.forkClaudeSessionRegistry.updateEnded(
                                chatID: id, expected: entry, ended: true)
                            try Task.checkCancellation()
                            try await core.forkClaudeSessionHost.remove(id: entry.shortID)
                            try Task.checkCancellation()
                        }
                        guard let latest = try core.forkClaudeSessionRegistry.cachedEntry(chatID: id),
                            latest.matchesSession(entry)
                        else { continue }
                        if preservingPinned, core.chatHistory.conversation(id: id)?.isPinned == true {
                            if !self.isEnded(chatID: id) { _ = try self.provider(chatID: id) }
                            continue
                        }
                        try await core.forkClaudeSessionRegistry.unregister(chatID: id)
                        try Task.checkCancellation()
                        self.endedChats.remove(id)
                        self.revision += 1
                    }
                    if preservingPinned, core.chatHistory.conversation(id: id)?.isPinned == true { continue }
                    completion([id])
                } catch is CancellationError {
                    return
                } catch {
                    self.revision += 1
                    core.showMessage(error.localizedDescription, tone: .danger)
                    if !self.isEnded(chatID: id) {
                        do { _ = try self.provider(chatID: id) } catch {
                            Self.logger.error("Could not reconnect Claude after a failed chat deletion")
                        }
                    }
                }
            }
        }
        return true
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
            var entry = try? core.forkClaudeSessionRegistry.cachedEntry(chatID: chatID)
        else {
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
            return [
                PopoverMenuItem(
                    title: "Resume", systemImage: "play", isLoading: busy,
                    isEnabled: FileManager.default.fileExists(atPath: entry.transcriptPath)
                ) { [weak self] in self?.resume(chatID: chatID) }
            ]
        }
        return [
            PopoverMenuItem(title: "Open in Terminal", systemImage: "terminal", isEnabled: !busy) {
                [weak self] in self?.openInTerminal(chatID: chatID)
            },
            PopoverMenuItem(
                title: "End Session", systemImage: "stop", isLoading: busy, isDestructive: true
            ) { [weak self] in self?.endSession(chatID: chatID) }
        ]
    }

    func openInTerminal(chatID: UUID) {
        guard let core, let entry = entry(chatID: chatID), !isEnded(chatID: chatID),
            !isBusy(chatID: chatID), !attachTerminals.contains(chatID)
        else { return }
        perform(chatID: chatID) { [weak self, weak core] in
            guard let self, let core else { throw CancellationError() }
            let executable = try await core.forkClaudeSessionHost.resolveExecutable()
            try Task.checkCancellation()
            guard let current = self.entry(chatID: chatID), current.sessionID == entry.sessionID,
                current.shortID == entry.shortID, current.ended != true
            else {
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
            !isBusy(chatID: chatID)
        else { return }
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
            !isBusy(chatID: chatID)
        else { return }
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
                chatID: chatID,
                entry: ForkClaudeSessionRegistry.Entry(
                    shortID: handle.id, sessionID: handle.sessionID, transcriptPath: transcript,
                    folder: entry.folder,
                    readOffset: transcript == entry.transcriptPath ? entry.readOffset : 0,
                    ended: false))
            try Task.checkCancellation()
            self.endedChats.remove(chatID)
            self.revision += 1
            _ = try self.provider(chatID: chatID)
        }
    }

    private func perform(chatID: UUID, operation: @escaping @MainActor () async throws -> Void) {
        let generation = UUID()
        if reconciliationGeneration != nil { lifecycleExcludedChats.insert(chatID) }
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
            let terminal = core?.terminalInstances.instances.first(where: { $0.id == id })
        {
            core?.terminalInstances.close(terminal)
        }
        terminalIDs[chatID] = nil
        setAttachTerminalOpen(false, chatID: chatID)
    }

    func queuedCount(chatID: UUID) -> Int { connections[chatID]?.writer.queuedCount ?? 0 }

    func stop() {
        reconciliationTask?.cancel()
        reconciliationTask = nil
        reconciliationGeneration = nil
        lifecycleExcludedChats = []
        deletionTask?.cancel()
        deletionTask = nil
        deletionGeneration = nil
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
        core.chatHistory.save(
            AIChatState.appendingClaudeTurn(user: user, assistant: assistant, to: session, waiting: false))
    }
}
