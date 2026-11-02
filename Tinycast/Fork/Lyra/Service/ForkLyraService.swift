import AppKit

@MainActor
final class ForkLyraService {
    struct Result: Sendable { let text: String; let applied: Bool }
    let preferences: ForkLyraSettings
    let server: ForkProcessSupervisor
    private let policy: ForkPolicyStore
    private let ai: AISettingsStore
    private let clipboard: ClipboardManager
    private let provider: (AIModelSelection) throws -> any AIProvider
    private let source = ForkLyraFocusObserver()
    private var generation = 0
    private(set) var isApplying = false

    init(preferences: ForkLyraSettings, server: ForkProcessSupervisor, policy: ForkPolicyStore, ai: AISettingsStore,
         clipboard: ClipboardManager, provider: @escaping (AIModelSelection) throws -> any AIProvider) {
        self.preferences = preferences
        self.server = server
        self.policy = policy
        self.ai = ai
        self.clipboard = clipboard
        self.provider = provider
    }

    func invalidate() { generation += 1 }

    func rewrite(mode: ForkLyraMode, target: ForkLyraArguments.Target, apply: Bool) async throws -> Result {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier != ForkKittySelectionSource.bundleID,
            let focused = ForkLyraFocusObserver.focusedElement(),
            let snapshot = ForkLyraFocusObserver.snapshot(focused) else { throw failure() }
        return try await rewrite(mode: mode, snapshot: snapshot, target: target, apply: apply)
    }

    func rewrite(mode: ForkLyraMode, snapshot: ForkLyraTextSnapshot,
                 target: ForkLyraArguments.Target = .automatic, apply: Bool = false,
                 policy snapshotPolicy: ForkPolicySnapshot? = nil,
                 onUpdate: @escaping @MainActor (String) -> Void = { _ in }) async throws -> Result {
        guard let activePolicy = snapshotPolicy ?? ForkPolicySnapshot.current ?? policy.snapshot,
            activePolicy.policy.availableModes.contains(mode) else { throw failure() }
        return try await ForkTrace.run(.lyra, category: .lyra,
                                      fields: .init(length: snapshot.value.count, policyVersion: activePolicy.version)) {
            guard preferences.enabled, !isApplying,
                NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier != ForkKittySelectionSource.bundleID,
                snapshot.isCurrent(),
                let app = NSRunningApplication(processIdentifier: snapshot.pid) else { throw failure() }
            let version = generation
            let selection = await source.read(from: app)
            try validate(snapshot, generation: version)
            guard let selection else { throw failure() }
            let range: NSRange
            switch target {
            case .automatic: range = mode == .fix ? snapshot.wholeRange : snapshot.targetRange
            case .selection:
                guard snapshot.selection.length > 0 else { throw failure() }
                range = snapshot.selection
            case .field: range = snapshot.wholeRange
            }
            let text = target == .automatic && mode != .fix
                ? selection.text : (snapshot.value as NSString).substring(with: range)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure() }
            if mode == .fix || target == .selection {
                let limits = target == .selection ? activePolicy.policy.selection : activePolicy.policy.fix.limits
                guard limits.accepts(text) else { throw failure() }
            }
            let result = try await complete(mode: mode, text: text, policy: activePolicy,
                                            validate: { try self.validate(snapshot, generation: version) }, onUpdate: onUpdate)
            var applied = false
            if apply { applied = try await self.apply(result, snapshot: snapshot, range: range) }
            return Result(text: result, applied: applied)
        }
    }

    func rewrite(mode: ForkLyraMode, text: String, policy activePolicy: ForkPolicySnapshot,
                 isCurrent: @escaping @MainActor () -> Bool,
                 onUpdate: @escaping @MainActor (String) -> Void = { _ in }) async throws -> Result {
        guard activePolicy.policy.panelModes.contains(mode),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure() }
        let version = generation
        return try await ForkTrace.run(.lyra, category: .lyra,
                                      fields: .init(length: text.count, policyVersion: activePolicy.version)) {
            let result = try await complete(mode: mode, text: text, policy: activePolicy, validate: {
                try Task.checkCancellation()
                guard self.preferences.enabled, !self.isApplying, self.generation == version, isCurrent() else {
                    throw self.failure()
                }
            }, onUpdate: onUpdate)
            return Result(text: result, applied: false)
        }
    }

    private func complete(mode: ForkLyraMode, text: String, policy activePolicy: ForkPolicySnapshot,
                          validate: @MainActor () throws -> Void,
                          onUpdate: @MainActor (String) -> Void) async throws -> String {
        try validate()
        guard let route = activePolicy.policy.routing[mode], let prompt = activePolicy.prompts[mode] else { throw failure() }
        let connectionID: UUID
        switch route {
        case .local: connectionID = preferences.connectionID
        case .connection(let id): connectionID = id
        }
        guard let connection = ai.connection(id: connectionID), let model = connection.models.first else { throw failure() }
        let local = connectionID == preferences.connectionID
        if local {
            try await server.start(modelPath: preferences.modelPath)
            try validate()
        }
        let selectionRoute = AIModelSelection.api(connection: connectionID, model: model, effort: "none")
        let client = try provider(selectionRoute)
        let request = AIRequest(instructions: prompt,
                                messages: [AIMessage(role: .user, text: "<input>\n\(text)\n</input>")],
                                maxOutputTokens: 2_048, requiresCompleteText: true, localRewrite: local)
        let requestSpan = ForkTrace.begin(.lyra, category: .lyra, step: .modelRequest)
        var raw = ""
        var finished = false
        var outcome = ForkEvent.Outcome.failed
        defer { requestSpan.end(Task.isCancelled ? .cancelled : outcome, fields: .init(length: raw.count)) }
        for try await event in client.stream(request) {
            try validate()
            switch event {
            case .text(let piece):
                if raw.isEmpty, !piece.isEmpty {
                    ForkTrace.Span(context: requestSpan.context, category: .lyra, step: .firstToken,
                                   started: requestSpan.started).end(.success, fields: .init(length: piece.count))
                }
                raw += piece
                onUpdate(ForkLyraText.clean(raw))
            case .finished: finished = true
            case .toolCallRequested: throw failure()
            default: break
            }
        }
        try validate()
        let result = ForkLyraText.clean(raw)
        guard finished, !result.isEmpty else { throw failure() }
        outcome = .success
        return result
    }

    func apply(_ text: String, snapshot: ForkLyraTextSnapshot, range: NSRange) async throws -> Bool {
        try validate(snapshot, generation: generation)
        guard !isApplying, let app = NSRunningApplication(processIdentifier: snapshot.pid),
            app.bundleIdentifier != ForkKittySelectionSource.bundleID else { throw failure() }
        isApplying = true
        defer { isApplying = false }
        let sink: any ForkTextSink = ForkLyraTextSink(snapshot: snapshot, range: range, clipboardManager: clipboard)
        let span = ForkTrace.begin(.lyra, category: .lyra, step: .insertion)
        let applied = await sink.replaceSelection(in: app, with: text)
        span.end(applied ? .success : .failed, fields: .init(length: text.count))
        guard applied else { throw failure() }
        return true
    }

    private func validate(_ snapshot: ForkLyraTextSnapshot, generation version: Int) throws {
        try Task.checkCancellation()
        guard preferences.enabled, generation == version,
            NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier != ForkKittySelectionSource.bundleID,
            snapshot.isCurrent() else { throw failure() }
    }

    private func failure() -> AIProviderError {
        .unavailable(String(localized: "The rewrite could not be completed. Check Lyra settings and the focused field."))
    }
}
