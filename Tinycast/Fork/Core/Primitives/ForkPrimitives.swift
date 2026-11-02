import AppKit

@MainActor
final class ForkPrimitives {
    private struct Target {
        let app: NSRunningApplication
        let snapshot: ForkLyraTextSnapshot?
        let text: String
    }

    private struct Interaction {
        let owner: UUID
        let expires: Date
        var choice: String?
    }

    private unowned let core: AppCore
    private let handles = ForkTargetHandleStore<Target>()
    private let panels = QuickActionPanelController()
    private var interactions: [String: Interaction] = [:]
    private var visible: String?
    private var expiry: Task<Void, Never>?
    private var applying: Task<Void, Never>?
    private var applyingID: String?
    private var replacement: Task<Bool, Never>?
    private var replacing = false

    init(core: AppCore) { self.core = core }

    func stop() {
        expiry?.cancel()
        expiry = nil
        applying?.cancel()
        replacement?.cancel()
        applying = nil
        dismissVisible()
        handles.removeAll()
        interactions.removeAll()
    }

    func stopForTermination() async {
        let pending = replacement
        let pendingUI = applying
        stop()
        await pendingUI?.value
        _ = await pending?.value
    }

    func read(_ call: AutomationCall) async throws -> JSONValue {
        guard let owner = call.caller.clientID else { throw Failure.refused }
        let requested = call.arguments["target"]?.stringValue
        let frontmost = NSWorkspace.shared.frontmostApplication
        let target = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? core.paletteCoordinator.targetApp : frontmost
        guard let target, !target.isTerminated,
            target.processIdentifier != NSRunningApplication.current.processIdentifier,
            requested == nil || requested == target.bundleIdentifier else { throw Failure.refused }
        guard Permissions.ensureAccessibility() else { throw Failure.refused }
        let snapshot = ForkLyraFocusObserver.focusedElement().flatMap(ForkLyraFocusObserver.snapshot)
        let result = await ForkSelectionAdapters.read(from: target) { [core] app in
            if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette() }
            return await core.textInjector.copySelection(from: app)
        }
        try Task.checkCancellation()
        guard !target.isTerminated, let selection = result.selection, !selection.text.isEmpty else { throw Failure.refused }
        let stable = snapshot.flatMap {
            $0.pid == target.processIdentifier && $0.selection.length > 0 && $0.isCurrent()
                && $0.targetText == selection.text ? $0 : nil
        }
        let handle = handles.insert(Target(app: target, snapshot: stable, text: selection.text), owner: owner)
        return .object([
            "text": .string(selection.text), "source": .string(selection.source.rawValue),
            "bundleID": .string(target.bundleIdentifier ?? ""), "handle": .string(handle)
        ])
    }

    func perform(_ call: AutomationCall) async -> AutomationOutcome {
        do {
            if call.operation.name == ForkSelectionOperations.selectionRead.name { return .value(try await read(call)) }
            if call.operation.name == ForkPrimitiveOperations.modelComplete.name {
                let arguments = try ForkModelArguments(arguments: call.arguments)
                return .value(.object(["text": .string(try await ForkModelService.complete(arguments, core: core))]))
            }
            guard let owner = call.caller.clientID else { throw Failure.refused }
            if call.operation.name == ForkPrimitiveOperations.result.name { return try result(call.arguments, owner: owner) }
            guard let handle = call.arguments["handle"]?.stringValue,
                let text = call.arguments["text"]?.stringValue else { throw Failure.refused }
            if call.operation.name == ForkPrimitiveOperations.textReplace.name {
                return .value(.object(["applied": .bool(await replace(handle, text: text, owner: owner))]))
            }
            guard let target = handles.resolve(handle, owner: owner, isCurrent: { !$0.app.isTerminated }) else {
                throw Failure.refused
            }
            let isMarker = call.operation.name == ForkPrimitiveOperations.marker.name
            if isMarker {
                guard target.snapshot?.isCurrent() == true else { throw Failure.refused }
            } else {
                guard call.arguments["title"]?.stringValue != nil,
                    call.arguments["original"]?.stringValue == target.text,
                    call.arguments["showsDiff"]?.boolValue != nil else { throw Failure.refused }
            }
            dismissVisible()
            let id = UUID().uuidString
            interactions = interactions.filter { $0.value.expires > Date() }
            guard interactions.count < 128 else { throw Failure.refused }
            interactions[id] = Interaction(owner: owner, expires: Date().addingTimeInterval(120))
            visible = id
            if isMarker, let snapshot = target.snapshot {
                guard core.forkLyra.presentWorkflowMarker(snapshot: snapshot, text: text, apply: { [weak self] in
                    guard let self, visible == id, interactions[id]?.choice == nil else { return false }
                    return await replace(handle, text: text, owner: owner)
                }, completion: { [weak self] choice in
                    self?.complete(id, choice: choice)
                }) else { complete(id, choice: "dismissed"); throw Failure.refused }
            } else {
                guard let title = call.arguments["title"]?.stringValue,
                    call.arguments["original"]?.stringValue == target.text,
                    let showsDiff = call.arguments["showsDiff"]?.boolValue else { throw Failure.refused }
                let state = QuickActionPanelState(
                    action: .custom(CustomQuickAction(name: title, instructions: "")),
                    original: target.text, targetLanguage: Locale.current.language,
                    workflowShowsDiff: showsDiff)
                state.finish(text)
                let trace = ForkTrace.context
                panels.present(state, metrics: core.settings.interfaceSize.metrics, languages: [], onRetranslate: { _ in },
                    onReplace: { [weak self] replacement in
                        guard let self else { return }
                        applyingID = id
                        applying = Task { [weak self] in
                            guard let self, visible == id, interactions[id]?.choice == nil, !Task.isCancelled else { return }
                            let applied = await ForkTrace.$context.withValue(trace) {
                                await replace(handle, text: replacement, owner: owner)
                            }
                            complete(id, choice: applied ? "replace" : "dismissed")
                            if applyingID == id { applying = nil; applyingID = nil }
                        }
                    }, onCompletion: { [weak self] choice in
                        guard choice != "replace" else { return }
                        self?.complete(id, choice: choice)
                    })
            }
            expiry?.cancel()
            expiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                guard self?.visible == id else { return }
                self?.dismissVisible()
            }
            return .value(.object(["id": .string(id)]))
        } catch is CancellationError { return .toolError("Cancelled.") }
        catch { return .toolError("The workflow primitive was refused or failed.") }
    }

    private func replace(_ handle: String, text: String, owner: UUID) async -> Bool {
        guard !Task.isCancelled, !replacing, !core.forkLyra.service.isApplying,
            core.automation.clients.current(owner)?.scopes.contains(.selection) == true,
            let target = handles.resolve(handle, owner: owner, isCurrent: { $0.snapshot?.isCurrent() == true }),
            let snapshot = target.snapshot else { return false }
        handles.remove(handle)
        replacing = true
        core.forkLyra.setWorkflowWriting(true)
        defer {
            replacing = false
            replacement = nil
            core.forkLyra.setWorkflowWriting(false)
        }
        let sink = ForkLyraTextSink(snapshot: snapshot, range: snapshot.selection, clipboardManager: core.clipboardManager)
        let task = Task { @MainActor in await sink.replaceSelection(in: target.app, with: text) }
        replacement = task
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }
    }

    private func result(_ arguments: [String: JSONValue], owner: UUID) throws -> AutomationOutcome {
        guard let id = arguments["id"]?.stringValue, let interaction = interactions[id],
            interaction.owner == owner else { throw Failure.refused }
        if arguments["cancel"]?.boolValue == true || interaction.expires <= Date() {
            if visible == id { dismissVisible() }
            interactions[id] = nil
            return .value(.object(["pending": .bool(false), "choice": .string(interaction.choice ?? "dismissed")]))
        }
        var value: [String: JSONValue] = ["pending": .bool(interaction.choice == nil)]
        if let choice = interaction.choice { value["choice"] = .string(choice) }
        return .value(.object(value))
    }

    private func complete(_ id: String, choice: String) {
        guard interactions[id]?.choice == nil else { return }
        interactions[id]?.choice = choice
        if visible == id { visible = nil; expiry?.cancel(); expiry = nil }
    }

    private func dismissVisible() {
        guard let id = visible else { return }
        applying?.cancel()
        complete(id, choice: "dismissed")
        panels.dismiss()
        core.forkLyra.dismissWorkflowMarker()
    }

    private enum Failure: Error { case refused }
}
