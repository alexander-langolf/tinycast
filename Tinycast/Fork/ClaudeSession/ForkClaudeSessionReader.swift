import Darwin
import Foundation

@MainActor
final class ForkClaudeSessionReader {
    private struct Submission {
        let token: UUID
        let text: String
        var consumed = false
        var ownsFirstTurn = false
    }

    private struct Turn {
        let user: String
        let owner: UUID?
        let readOffset: UInt64
        var assistant = ""
        var final = false
    }

    let chatID: UUID
    private(set) var isTurnRunning = false
    private(set) var isApprovalWaiting = false
    var foreignTurn: (@MainActor (String, String) -> Void)?
    var approvalChanged: (@MainActor (String?) -> Void)?
    var onFailure: (@MainActor (Error) -> Void)?
    var hasPendingForeignTurns: (@MainActor () -> Bool)?

    private let entry: ForkClaudeSessionRegistry.Entry
    private let registry: ForkClaudeSessionRegistry
    private let eventsURL: URL
    private var eventOffset: UInt64 = 0
    private var transcriptOffset: UInt64
    private var persistedOffset: UInt64
    private var initialized = false
    private var stopped = false
    private var pendingForeignOffset: UInt64?
    private var failure: Error?
    private var approvalTool: String?
    private var requestedTool: String?
    private var turn: Turn?
    private var submission: Submission?
    private var confirmed: Set<UUID> = []
    private var streams: [UUID: AIProviderStream.Continuation] = [:]
    private var stopDeadline: ContinuousClock.Instant?
    private var polling: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Error>?
    private var watcher: (any DispatchSourceFileSystemObject)?

    init(
        chatID: UUID, entry: ForkClaudeSessionRegistry.Entry,
        registry: ForkClaudeSessionRegistry, eventsURL: URL
    ) {
        self.chatID = chatID
        self.entry = entry
        self.registry = registry
        self.eventsURL = eventsURL
        transcriptOffset = entry.readOffset
        persistedOffset = entry.readOffset
    }

    isolated deinit {
        polling?.cancel()
        stopTask?.cancel()
        refreshTask?.cancel()
        watcher?.cancel()
        for stream in streams.values { stream.finish(throwing: CancellationError()) }
    }

    func start() {
        guard polling == nil else { return }
        stopped = false
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await self?.refresh()
                    try await Task.sleep(for: .milliseconds(500))
                } catch is CancellationError {
                    return
                } catch {
                    self?.fail(error)
                    return
                }
            }
        }
    }

    func stop() {
        stopped = true
        polling?.cancel()
        polling = nil
        stopTask?.cancel()
        stopTask = nil
        refreshTask?.cancel()
        watcher?.cancel()
        watcher = nil
        for stream in streams.values { stream.finish(throwing: CancellationError()) }
        streams = [:]
    }

    func events(token: UUID) -> AIProviderStream {
        let pair = AIProviderStream.makeStream()
        if let failure {
            pair.continuation.finish(throwing: failure)
        } else {
            streams[token] = pair.continuation
        }
        return pair.stream
    }

    func arm(token: UUID, text: String) {
        confirmed.removeAll()
        submission = Submission(token: token, text: text)
    }

    func armInitial(token: UUID, text: String) {
        arm(token: token, text: text)
        submission?.ownsFirstTurn = true
    }

    var hasQueuedChatTurn: Bool {
        streams.keys.contains { $0 != submission?.token || submission?.consumed != true }
    }

    func delivered(token: UUID) -> Bool { confirmed.contains(token) }

    func release(token: UUID) {
        streams.removeValue(forKey: token)?.finish()
        confirmed.remove(token)
    }

    func refresh() async throws {
        guard !stopped else { throw CancellationError() }
        if let failure { throw failure }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.read() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func read() async throws {
        installWatcher()
        let hooks = try await ForkClaudeSessionTail.read(url: eventsURL, offset: eventOffset)
        let events = try await ForkClaudeSessionTranscript.hooks(hooks.lines, sessionID: entry.sessionID)
        try Task.checkCancellation()
        for event in events { receive(event) }
        eventOffset = hooks.offset
        if !initialized || isTurnRunning || !events.isEmpty {
            let tail = try await ForkClaudeSessionTail.read(
                url: URL(fileURLWithPath: entry.transcriptPath), offset: transcriptOffset)
            let records = try await ForkClaudeSessionTranscript.records(
                tail.lines, sessionID: entry.sessionID, offset: transcriptOffset)
            try Task.checkCancellation()
            for record in records { receive(record) }
            transcriptOffset = tail.offset
        }
        initialized = true
        if let deadline = stopDeadline, turn?.final == true || ContinuousClock.now >= deadline {
            finishTurn()
        }
        var savedOffset = turn.flatMap { $0.owner == nil ? $0.readOffset : nil } ?? transcriptOffset
        if hasPendingForeignTurns?() == true, let pendingForeignOffset {
            savedOffset = min(savedOffset, pendingForeignOffset)
        } else {
            pendingForeignOffset = nil
        }
        if savedOffset != persistedOffset {
            try await registry.updateReadOffset(
                chatID: chatID, offset: savedOffset, sessionID: entry.sessionID,
                transcriptPath: entry.transcriptPath)
            try Task.checkCancellation()
            persistedOffset = savedOffset
        }
    }

    private func receive(_ hook: ForkClaudeSessionTranscript.Hook) {
        switch hook.name {
        case "UserPromptSubmit":
            isTurnRunning = true
            setApproval(nil)
            stopDeadline = nil
            stopTask?.cancel()
            stopTask = nil
            if let submission, let prompt = hook.prompt,
                ForkClaudeSessionTranscript.promptText(prompt) == submission.text
            {
                confirmed.insert(submission.token)
            }
        case "PreToolUse":
            isTurnRunning = true
            requestedTool = hook.tool
        case "PermissionRequest":
            isTurnRunning = true
            setApproval(hook.tool ?? requestedTool ?? "tool")
        case "Notification" where hook.permissionPrompt:
            setApproval(hook.tool ?? requestedTool ?? "tool")
        case "PostToolUse": setApproval(nil)
        case "Stop":
            setApproval(nil)
            stopDeadline = ContinuousClock.now.advanced(by: .seconds(2))
            stopTask?.cancel()
            stopTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(2))
                    try await self?.refresh()
                } catch is CancellationError {
                    return
                } catch { self?.fail(error) }
            }
        default: break
        }
    }

    private func receive(_ record: ForkClaudeSessionTranscript.Record) {
        switch record {
        case .user(let user, let offset):
            if turn != nil { finishTurn(clearStop: false) }
            let owner = submission.flatMap {
                !$0.consumed && ($0.ownsFirstTurn || $0.text == user) ? $0.token : nil
            }
            if owner != nil { submission?.consumed = true }
            turn = Turn(user: user, owner: owner, readOffset: offset)
            isTurnRunning = true
        case .assistant(let events, let final):
            if turn == nil { turn = Turn(user: "", owner: nil, readOffset: persistedOffset) }
            isTurnRunning = true
            for event in events {
                if case .text(let text) = event { turn?.assistant += text }
                emit(event)
            }
            turn?.final = final
        case .results(let events):
            for event in events { emit(event) }
        }
    }

    private func emit(_ event: AIStreamEvent) {
        guard let owner = turn?.owner else { return }
        streams[owner]?.yield(event)
    }

    private func finishTurn(clearStop: Bool = true) {
        if let turn {
            if let owner = turn.owner {
                if let stream = streams.removeValue(forKey: owner) {
                    stream.yield(.finished)
                    stream.finish()
                }
            } else if !turn.user.isEmpty || !turn.assistant.isEmpty {
                foreignTurn?(turn.user, turn.assistant)
                if hasPendingForeignTurns?() == true {
                    pendingForeignOffset = min(pendingForeignOffset ?? turn.readOffset, turn.readOffset)
                }
            }
        }
        turn = nil
        if clearStop {
            isTurnRunning = false
            setApproval(nil)
            stopDeadline = nil
            stopTask?.cancel()
            stopTask = nil
        }
    }

    private func setApproval(_ tool: String?) {
        isApprovalWaiting = tool != nil
        guard approvalTool != tool else { return }
        approvalTool = tool
        approvalChanged?(tool)
    }

    private func fail(_ error: Error) {
        polling?.cancel()
        stopTask?.cancel()
        watcher?.cancel()
        watcher = nil
        failure = error
        for stream in streams.values { stream.finish(throwing: error) }
        streams = [:]
        onFailure?(error)
    }

    private func installWatcher() {
        guard watcher == nil else { return }
        let descriptor = open(eventsURL.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let changes = self.watcher?.data ?? []
                if changes.contains(.rename) || changes.contains(.delete) {
                    self.watcher?.cancel()
                    self.watcher = nil
                    self.eventOffset = 0
                }
                do { try await self.refresh() } catch is CancellationError {
                    return
                } catch { self.fail(error) }
            }
        }
        source.setCancelHandler { close(descriptor) }
        watcher = source
        source.resume()
    }
}
