import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class ForkLyraCoordinator {
    @ObservationIgnored var onPresentationChange: ((Bool) -> Void)?
    var ownsTypingSurface: Bool { ui.kind != .hidden || service.isApplying || applyingWorkflow || workflowWriting }
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
    @ObservationIgnored private var interaction: ForkTrace.Context?
    @ObservationIgnored private var selectedMode = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var configuration: String?
    @ObservationIgnored private var presentationStartedAt: TimeInterval = 0

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
        ui.onModeStep = { [weak self] step in
            guard let self else { return }
            rewritePanel(mode: (selectedMode + step + panelModeCount) % panelModeCount)
        }
        ui.onKindChange = { [weak self] kind in
            guard let self else { return }
            presentationStartedAt = ProcessInfo.processInfo.systemUptime
            onPresentationChange?(ownsTypingSurface)
            updateKeys(kind)
        }
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
        }
    }

    private func startWatching() {
        _ = Permissions.ensureAccessibility()
        inputMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let key = event.type == .keyDown ? Int(event.keyCode) : nil
            let timestamp = event.timestamp
            Task { @MainActor [weak self] in self?.input(key: key, timestamp: timestamp) }
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
        if let target, target.isCurrent() { current = target; return }
        let previous = current
        current = text
        guard let text else { dismiss(reason: .focusChanged); return }
        if change != .focus, let previous, CFEqual(previous.element, text.element),
            previous.value == text.value, previous.selection == text.selection { return }
        dismiss(reason: change == .focus ? .focusChanged : change == .selection ? .selectionChanged : .inputChanged)
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
        suggestion = text
        interaction = ForkTrace.context
        workflowApply = apply
        workflowCompletion = completion
        ui.showMarker(at: snapshot.anchor, caretKnown: snapshot.caretKnown)
        ForkTrace.begin(.workflow, category: .workflows, step: .marker).end(.success)
        return true
    }

    func setWorkflowWriting(_ writing: Bool) {
        workflowWriting = writing
        onPresentationChange?(ownsTypingSurface)
    }

    func dismissWorkflowMarker() {
        if applyingWorkflow { applyTask?.cancel() }
        if workflowCompletion != nil { dismiss() }
    }

    func openPanel() {
        let trace = ForkTrace.Context(id: UUID(), operation: .lyra, clientID: nil, policyVersion: policy.snapshot?.version)
        ForkTrace.$context.withValue(trace) {
            ForkTrace.begin(.lyra, category: .lyra, step: .trigger).end(.started)
            guard preferences.enabled else { panelDecision(.notEnabled); return }
            guard !service.isApplying, !workflowWriting, !applyingWorkflow else { panelDecision(.busy); return }
            guard let activePolicy = policy.snapshot else { panelDecision(.noPolicy); return }
            guard activePolicy.policy.panelModes.first == .fix else { panelDecision(.noFix); return }
            dismiss()
            guard let focused = ForkLyraFocusObserver.focusedTarget(rejected: { panelDecision($0) }) else { return }
            let app = focused.app
            let role = ForkLyraFocusObserver.attribute(focused.element, kAXRoleAttribute) as? String
            @MainActor func reject(_ reason: ForkEvent.Reason) {
                panelDecision(reason, bundleID: app.bundleIdentifier, role: role, pid: app.processIdentifier)
            }
            panelPolicy = activePolicy
            interaction = trace
            selectedMode = 0
            if app.bundleIdentifier == ForkKittySelectionSource.bundleID {
                ForkTrace.begin(.lyra, category: .selection, step: .selectionRead)
                    .end(.started, fields: .init(bundleID: app.bundleIdentifier, pid: app.processIdentifier))
                openKittyPanel(from: app, mouse: NSEvent.mouseLocation)
                return
            }
            guard let snapshot = ForkLyraFocusObserver.snapshot(focused.element, rejected: reject) else {
                dismiss()
                return
            }
            guard snapshot.pid == app.processIdentifier else { reject(.pidMismatch); dismiss(); return }
            guard !snapshot.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reject(.emptyField)
                dismiss()
                AppCore.shared.showMessage(String(localized: "Nothing to check"), tone: .neutral)
                return
            }
            current = snapshot
            target = snapshot
            ui.showRewrite(at: snapshot.anchor, caretKnown: snapshot.caretKnown, original: snapshot.targetText)
            ForkTrace.begin(.lyra, category: .lyra, step: .offer).end(.success, fields: .init(
                length: snapshot.targetText.count, bundleID: app.bundleIdentifier, caretKnown: snapshot.caretKnown,
                role: snapshot.role, pid: snapshot.pid))
            rewritePanel(mode: selectedMode)
        }
    }

    private func panelDecision(_ reason: ForkEvent.Reason, bundleID: String? = nil,
                               role: String? = nil, pid: pid_t? = nil) {
        ForkTrace.begin(.lyra, category: .lyra, step: .decision)
            .end(.skipped, fields: .init(bundleID: bundleID, reason: reason, role: role, pid: pid))
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
                guard !Task.isCancelled, generation == version else { panelDecision(.superseded); return }
                guard !app.isTerminated,
                    ForkLyraFocusObserver.focusedTarget()?.app.processIdentifier == app.processIdentifier else {
                    panelDecision(.staleTarget, bundleID: app.bundleIdentifier, pid: app.processIdentifier)
                    return
                }
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
                    panelDecision(reader.failure == .empty ? .emptySelection : .selectionUnavailable,
                                  bundleID: app.bundleIdentifier, pid: app.processIdentifier)
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
                    && ForkLyraFocusObserver.focusedTarget()?.app.processIdentifier == kittyTarget.app.processIdentifier
            }
            return target?.isCurrent() == true
        }
        generation += 1
        let version = generation
        request?.cancel()
        suggestion = nil
        selectedMode = mode
        ui.updateMode(panelPolicy.policy.panelModes[mode])
        ui.updateRewrite(nil)
        let trace = interaction
        request = Task { [weak self] in
            guard let self else { return }
            await ForkTrace.$context.withValue(trace) {
                defer { if generation == version { request = nil } }
                do {
                    let onUpdate: @MainActor (String) -> Void = { [weak self] partial in
                        guard let self, generation == version, ui.kind == .rewrite else { return }
                        ui.updateRewrite(partial.isEmpty ? nil : partial)
                    }
                    let result = try await service.rewrite(mode: panelPolicy.policy.panelModes[mode], text: text,
                                                           policy: panelPolicy, isCurrent: isCurrent, onUpdate: onUpdate)
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

    private func input(key: Int?, timestamp: TimeInterval) {
        guard preferences.enabled, !service.isApplying, !workflowWriting else { return }
        guard timestamp > presentationStartedAt else { return }
        guard let key else { if !ui.containsMouse() { dismiss(reason: .inputChanged) }; return }
        let registered = registeredKeys(ui.kind)
        if !registered.contains(key) { dismiss(reason: .inputChanged) }
    }

    private func registeredKeys(_ kind: ForkLyraSuggestionController.Kind) -> [Int] {
        switch kind {
        case .hidden: []
        case .marker, .preview: [kVK_Tab, kVK_Escape]
        case .rewrite: [kVK_Tab, kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter, kVK_ANSI_1, kVK_ANSI_2,
                        kVK_ANSI_3, kVK_ANSI_4, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
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
            case kVK_Tab, kVK_Return, kVK_ANSI_KeypadEnter: ui.acceptRewrite { apply() }
            case kVK_ANSI_1: rewritePanel(mode: 0)
            case kVK_ANSI_2: rewritePanel(mode: 1)
            case kVK_ANSI_3: rewritePanel(mode: 2)
            case kVK_ANSI_4: rewritePanel(mode: 3)
            case kVK_LeftArrow, kVK_UpArrow: rewritePanel(mode: (selectedMode + panelModeCount - 1) % panelModeCount)
            case kVK_RightArrow, kVK_DownArrow: rewritePanel(mode: (selectedMode + 1) % panelModeCount)
            default: break
            }
        } else if key == kVK_Tab {
            if ui.kind == .marker, let suggestion, let target { ui.showPreview(suggestion, original: target.targetText) }
            else if ui.kind == .preview { apply() }
        }
    }

    private func apply() {
        guard let target, let suggestion else { return }
        let range = target.targetRange
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

    private func dismiss(reason: ForkEvent.Reason? = nil) {
        generation += 1
        request?.cancel()
        request = nil
        let completion = workflowCompletion
        workflowCompletion = nil
        workflowApply = nil
        completion?("dismissed")
        panelPolicy = nil
        if ui.kind != .hidden, let interaction {
            ForkTrace.$context.withValue(interaction) {
                ForkTrace.begin(.lyra, category: .lyra, step: .dismissal).end(.success, fields: .init(reason: reason))
            }
        }
        target = nil
        kittyTarget = nil
        suggestion = nil
        interaction = nil
        ui.dismiss()
    }
}
