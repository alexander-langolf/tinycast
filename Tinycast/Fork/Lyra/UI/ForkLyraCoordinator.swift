import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class ForkLyraCoordinator {
    let preferences: ForkLyraSettings
    let server: ForkProcessSupervisor
    let service: ForkLyraService
    @ObservationIgnored private let policy: ForkPolicyStore
    @ObservationIgnored private var workflowApply: (@MainActor () async -> Bool)?
    @ObservationIgnored private var applyingWorkflow = false
    @ObservationIgnored private var workflowWriting = false
    @ObservationIgnored private var workflowCompletion: ((String) -> Void)?
    @ObservationIgnored private var panelPolicy: ForkPolicySnapshot?
    @ObservationIgnored private let ai: AISettingsStore
    @ObservationIgnored private let focus = ForkLyraFocusObserver()
    @ObservationIgnored private let ui = ForkLyraSuggestionController()
    @ObservationIgnored private let keys = HotKeyCenter(signature: 0x4C59_5241)
    @ObservationIgnored private var inputMonitor: Any?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var current: ForkLyraTextSnapshot?
    @ObservationIgnored private var target: ForkLyraTextSnapshot?
    @ObservationIgnored private var kittyTarget: (text: String, app: NSRunningApplication)?
    @ObservationIgnored private var suggestion: String?
    @ObservationIgnored private var fixesSelection = false
    @ObservationIgnored private var interaction: ForkTrace.Context?
    @ObservationIgnored private var selectedMode = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var configuration: String?

    init(ai: AISettingsStore, clipboard: ClipboardManager, policy: ForkPolicyStore,
         provider: @escaping (AIModelSelection) throws -> any AIProvider) {
        let preferences = ForkLyraSettings()
        let server = ForkProcessSupervisor(name: "llama-server", control: ForkLlamaServer())
        self.preferences = preferences
        self.server = server
        self.ai = ai
        self.policy = policy
        service = ForkLyraService(preferences: preferences, server: server, policy: policy, ai: ai,
                                  clipboard: clipboard, provider: provider)
        focus.onChange = { [weak self] text, change in self?.textChanged(text, change: change) }
        ui.onDismiss = { [weak self] in self?.dismiss() }
        ui.onKindChange = { [weak self] in self?.updateKeys($0) }
    }

    func start() {
        policy.onChange = { [weak self] in
            self?.service.invalidate()
            self?.dismiss()
        }
        preferences.start()
        ai.save(preferences.connection())
        preferences.onChange = { [weak self] in self?.settingsChanged() }
        settingsChanged()
    }

    private func settingsChanged() {
        service.invalidate()
        dismiss()
        let next = "\(preferences.enabled):\(preferences.modelPath)"
        guard configuration != next else { return }
        configuration = next
        stopWatching()
        let previous = lifecycle
        previous?.cancel()
        lifecycle = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await server.stop()
            guard !Task.isCancelled, preferences.enabled else { return }
            startWatching()
            do { try await server.start(modelPath: preferences.modelPath) }
            catch {
                if !Task.isCancelled { ForkTrace.begin(.lyra, category: .lyra, step: .readiness).end(.failed) }
            }
        }
    }

    private func startWatching() {
        _ = Permissions.ensureAccessibility()
        inputMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let key = event.type == .keyDown ? Int(event.keyCode) : nil
            Task { @MainActor [weak self] in self?.input(key: key) }
        }
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, preferences.enabled else { return }
                if Permissions.isAccessibilityTrusted() {
                    if !watching { focus.start(); watching = true }
                } else if watching { focus.stop(); watching = false; dismiss() }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private func stopWatching() {
        permissionTask?.cancel()
        permissionTask = nil
        focus.stop()
        watching = false
        updateKeys(.hidden)
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
    }

    func stop() {
        preferences.onChange = nil
        policy.onChange = nil
        lifecycle?.cancel()
        stopWatching()
        dismiss()
        service.invalidate()
    }

    func stopForTermination() async {
        stop()
        await lifecycle?.value
        await applyTask?.value
        await server.stop()
    }

    private func textChanged(_ text: ForkLyraTextSnapshot?, change: ForkLyraFocusObserver.Change) {
        guard !service.isApplying, !workflowWriting else { return }
        let previous = current
        current = text
        guard let text else { dismiss(); return }
        if change != .focus, let previous, CFEqual(previous.element, text.element),
            previous.value == text.value, previous.selection == text.selection { return }
        let changedValue = previous.map { CFEqual($0.element, text.element) && $0.value != text.value } ?? false
        let followsTypedCaret = change == .selection && text.selection.length == 0 && request != nil && ui.kind == .hidden
        dismiss()
        if change == .value || changedValue || followsTypedCaret { scheduleFix(text) }
    }

    private func scheduleFix(_ snapshot: ForkLyraTextSnapshot) {
        guard NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier != ForkKittySelectionSource.bundleID,
            preferences.enabled, preferences.fixEnabled, let activePolicy = policy.snapshot,
            activePolicy.policy.availableModes.contains(.fix),
            let delay = activePolicy.policy.fix.delay(for: snapshot.value) else { return }
        let original = snapshot.value
        let version = generation
        let trace = ForkTrace.Context(id: UUID(), operation: .lyra, clientID: nil, policyVersion: activePolicy.version)
        interaction = trace
        request = Task { [weak self] in
            guard let self else { return }
            await ForkTrace.$context.withValue(trace) {
                ForkTrace.begin(.lyra, category: .lyra, step: .trigger).end(.started, fields: .init(length: snapshot.value.count))
                defer { if generation == version { request = nil } }
                do {
                    try await Task.sleep(for: delay)
                    let result = try await service.rewrite(
                        mode: .fix, snapshot: snapshot, policy: activePolicy)
                    try Task.checkCancellation()
                    guard generation == version, snapshot.isCurrent(),
                        ForkLyraText.normalized(result.text) != ForkLyraText.normalized(original) else { return }
                    target = snapshot
                    fixesSelection = false
                    suggestion = result.text
                    ui.showMarker(at: snapshot.anchor, caretKnown: snapshot.caretKnown)
                    ForkTrace.begin(.lyra, category: .lyra, step: .marker)
                        .end(.success, fields: .init(caretKnown: snapshot.caretKnown))
                } catch {
                    ForkTrace.begin(.lyra, category: .lyra, step: .trigger)
                        .end(error is CancellationError ? .cancelled : .failed)
                }
            }
        }
    }

    func presentWorkflowMarker(
        snapshot: ForkLyraTextSnapshot, text: String, apply: @escaping @MainActor () async -> Bool,
        completion: @escaping (String) -> Void
    ) -> Bool {
        guard preferences.enabled, !service.isApplying, !applyingWorkflow, !workflowWriting,
            snapshot.isCurrent() else { return false }
        dismiss()
        current = snapshot
        target = snapshot
        fixesSelection = true
        suggestion = text
        interaction = ForkTrace.context
        workflowApply = apply
        workflowCompletion = completion
        ui.showMarker(at: snapshot.anchor, caretKnown: snapshot.caretKnown)
        ForkTrace.begin(.workflow, category: .workflows, step: .marker).end(.success)
        return true
    }

    func setWorkflowWriting(_ writing: Bool) { workflowWriting = writing }

    func dismissWorkflowMarker() {
        if applyingWorkflow { applyTask?.cancel() }
        if workflowCompletion != nil { dismiss() }
    }

    func openPanel() {
        guard preferences.enabled, !service.isApplying, !workflowWriting, !applyingWorkflow, let activePolicy = policy.snapshot,
            !activePolicy.policy.panelModes.isEmpty else { return }
        dismiss()
        panelPolicy = activePolicy
        interaction = ForkTrace.Context(id: UUID(), operation: .lyra, clientID: nil, policyVersion: activePolicy.version)
        selectedMode = 0
        if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == ForkKittySelectionSource.bundleID {
            openKittyPanel(from: app, mouse: NSEvent.mouseLocation)
            return
        }
        guard let focused = ForkLyraFocusObserver.focusedElement(),
            let snapshot = ForkLyraFocusObserver.snapshot(focused),
            !snapshot.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        target = snapshot
        ui.showRewrite(at: snapshot.anchor, caretKnown: snapshot.caretKnown, original: snapshot.targetText)
        rewritePanel(mode: selectedMode)
    }

    private func openKittyPanel(from app: NSRunningApplication, mouse: CGPoint) {
        let version = generation
        let trace = interaction
        request = Task { [weak self] in
            guard let self else { return }
            await ForkTrace.$context.withValue(trace) {
                defer { if generation == version { request = nil } }
                let reader = ForkKittySelectionSource()
                var selection = await reader.read(from: app)
                guard !Task.isCancelled, generation == version, !app.isTerminated,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                if selection == nil, reader.failure == .empty, let latest = AppCore.shared.clipboardStore.items.first,
                    latest.kind == .text,
                    let text = ForkKittySelectionSource.clipboardFallback(
                        text: latest.text, sourceBundleID: latest.sourceBundleID, createdAt: latest.createdAt, now: .now) {
                    selection = ForkSelection(text: text, source: .clipboardBorrow)
                    ForkTrace.begin(.lyra, category: .selection, step: .copySelection)
                        .end(.success, fields: .init(length: text.count, bundleID: ForkKittySelectionSource.bundleID))
                }
                guard let selection else {
                    let message = reader.failure?.message
                    dismiss()
                    if let message { AppCore.shared.showMessage(message, tone: .danger) }
                    return
                }
                kittyTarget = (selection.text, app)
                ui.showRewrite(near: mouse, original: selection.text)
                rewritePanel(mode: selectedMode)
            }
        }
    }

    private func rewritePanel(mode: Int) {
        guard ui.kind == .rewrite, let panelPolicy, panelPolicy.policy.panelModes.indices.contains(mode),
            target != nil || kittyTarget != nil else { return }
        let target = target
        let kittyTarget = kittyTarget
        let text = kittyTarget?.text ?? target?.targetText ?? ""
        let isCurrent: @MainActor () -> Bool = {
            if let kittyTarget {
                return !kittyTarget.app.isTerminated
                    && NSWorkspace.shared.frontmostApplication?.processIdentifier == kittyTarget.app.processIdentifier
            }
            return target?.isCurrent() == true
        }
        generation += 1
        let version = generation
        request?.cancel()
        suggestion = nil
        selectedMode = mode
        ui.updateRewrite(nil)
        request = Task { [weak self] in
            guard let self else { return }
            await ForkTrace.$context.withValue(interaction) {
                ForkTrace.begin(.lyra, category: .lyra, step: .trigger).end(.started, fields: .init(length: text.count))
                defer { if generation == version { request = nil } }
                do {
                    let onUpdate: @MainActor (String) -> Void = { [weak self] partial in
                        guard let self, generation == version, ui.kind == .rewrite else { return }
                        ui.updateRewrite(partial.isEmpty ? nil : partial)
                    }
                    let result: ForkLyraService.Result
                    if kittyTarget != nil {
                        result = try await service.rewrite(mode: panelPolicy.policy.panelModes[mode], text: text,
                                                           policy: panelPolicy, isCurrent: isCurrent, onUpdate: onUpdate)
                    } else if let target {
                        result = try await service.rewrite(mode: panelPolicy.policy.panelModes[mode], snapshot: target,
                                                           policy: panelPolicy, onUpdate: onUpdate)
                    } else { return }
                    try Task.checkCancellation()
                    guard generation == version, ui.kind == .rewrite, isCurrent() else { return }
                    suggestion = result.text
                    ui.updateRewrite(result.text, isComplete: true)
                } catch {
                    guard !Task.isCancelled, generation == version else { return }
                    ui.updateRewrite(String(localized: "The rewrite could not be completed. Check Lyra settings and the focused field."), isError: true)
                }
            }
        }
    }

    private func input(key: Int?) {
        guard preferences.enabled, !service.isApplying, !workflowWriting else { return }
        guard let key else { if !ui.containsMouse() { dismiss() }; return }
        let registered = registeredKeys(ui.kind)
        if !registered.contains(key) { dismiss() }
    }

    private func registeredKeys(_ kind: ForkLyraSuggestionController.Kind) -> [Int] {
        switch kind {
        case .hidden: []
        case .marker, .preview: [kVK_Tab, kVK_Escape]
        case .rewrite: [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter, kVK_ANSI_1, kVK_ANSI_2,
                        kVK_ANSI_3, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        }
    }

    private func updateKeys(_ kind: ForkLyraSuggestionController.Kind) {
        let all = Set(registeredKeys(.marker) + registeredKeys(.rewrite))
        for key in all { keys.unregister(id: "fork.lyra.key.\(key)") }
        guard preferences.enabled else { return }
        for key in registeredKeys(kind) {
            keys.register(id: "fork.lyra.key.\(key)", shortcut: KeyShortcut(carbonKeyCode: key, carbonModifiers: 0)) { [weak self] _ in
                self?.handle(key)
            }
        }
    }

    private var panelModeCount: Int { max(1, panelPolicy?.policy.panelModes.count ?? 0) }

    private func handle(_ key: Int) {
        guard !service.isApplying, !workflowWriting else { return }
        if key == kVK_Escape { dismiss(); return }
        if ui.kind == .rewrite {
            switch key {
            case kVK_Return, kVK_ANSI_KeypadEnter: ui.acceptRewrite { apply(panel: true) }
            case kVK_ANSI_1: rewritePanel(mode: 0)
            case kVK_ANSI_2: rewritePanel(mode: 1)
            case kVK_ANSI_3: rewritePanel(mode: 2)
            case kVK_LeftArrow, kVK_UpArrow: rewritePanel(mode: (selectedMode + panelModeCount - 1) % panelModeCount)
            case kVK_RightArrow, kVK_DownArrow: rewritePanel(mode: (selectedMode + 1) % panelModeCount)
            default: break
            }
        } else if key == kVK_Tab {
            if ui.kind == .marker, let suggestion, let target { ui.showPreview(suggestion, original: target.targetText) }
            else if ui.kind == .preview { apply(panel: false) }
        }
    }

    private func apply(panel: Bool) {
        guard let target, let suggestion else { return }
        let range = panel || fixesSelection ? target.targetRange : target.wholeRange
        let trace = interaction
        let completion = workflowCompletion
        let workflowApply = workflowApply
        self.workflowApply = nil
        workflowCompletion = nil
        applyingWorkflow = completion != nil
        dismiss()
        applyTask = Task { [weak self] in
            guard let self else { return }
            await ForkTrace.$context.withValue(trace) {
                if let workflowApply {
                    completion?(await workflowApply() ? "applied" : "dismissed")
                    return
                }
                do {
                    _ = try await service.apply(suggestion, snapshot: target, range: range)
                    completion?("applied")
                } catch {
                    ForkTrace.begin(.lyra, category: .lyra, step: .insertion).end(.failed)
                    completion?("dismissed")
                }
            }
            applyingWorkflow = false
            applyTask = nil
        }
    }

    private func dismiss() {
        generation += 1
        request?.cancel()
        request = nil
        let completion = workflowCompletion
        workflowCompletion = nil
        workflowApply = nil
        completion?("dismissed")
        panelPolicy = nil
        fixesSelection = false
        if ui.kind != .hidden, let interaction {
            ForkTrace.$context.withValue(interaction) {
                ForkTrace.begin(.lyra, category: .lyra, step: .dismissal).end(.success)
            }
        }
        target = nil
        kittyTarget = nil
        suggestion = nil
        interaction = nil
        ui.dismiss()
    }
}
