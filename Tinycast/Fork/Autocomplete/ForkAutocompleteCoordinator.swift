import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class ForkAutocompleteCoordinator {
    let preferences = ForkAutocompleteSettings()
    private(set) var ready = false
    @ObservationIgnored private let clipboard: ClipboardManager
    @ObservationIgnored private let lyraIsPresenting: () -> Bool
    @ObservationIgnored private let focus = ForkLyraFocusObserver()
    @ObservationIgnored private let client = ForkAutocompleteClient()
    @ObservationIgnored private let ghost = ForkAutocompleteGhostController()
    @ObservationIgnored private let keys = HotKeyCenter(signature: 0x574F_5244)
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var refresh: Task<Void, Never>?
    @ObservationIgnored private var prediction: Task<Void, Never>?
    @ObservationIgnored private var learning: Task<Void, Never>?
    @ObservationIgnored private var insertion: Task<Void, Never>?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var previous: ForkLyraTextSnapshot?
    @ObservationIgnored private var target: ForkLyraTextSnapshot?
    @ObservationIgnored private var suffix: String?
    @ObservationIgnored private var fallbackAnchor: ForkAutocompleteGhostController.FallbackAnchor?
    @ObservationIgnored private var presentationKind: ForkEvent.PresentationKind?
    @ObservationIgnored private var presentedAt: TimeInterval?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var watching = false
    @ObservationIgnored private var configuredEnabled: Bool?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let identity = UUID().uuidString
    @ObservationIgnored private var decisions: [ForkEvent.Reason: (pid: pid_t?, time: ContinuousClock.Instant)] = [:]

    init(clipboard: ClipboardManager, lyraIsPresenting: @escaping () -> Bool) {
        self.clipboard = clipboard
        self.lyraIsPresenting = lyraIsPresenting
        focus.allowsApp = { [weak self] app in self?.preferences.allows(app.bundleIdentifier) == true }
        focus.allowsElement = { Self.readRejection($0) == nil }
        focus.onChange = { [weak self] _, change in
            guard let self else { return }
            if change == .focus { previous = nil; dismiss(reason: .focusChanged) }
            scheduleRefresh()
        }
    }

    func start() {
        guard !running else { return }
        running = true
        preferences.start()
        preferences.onChange = { [weak self] in self?.configure() }
        configure()
    }

    private func configure() {
        dismiss(reason: .settingsChanged)
        stopWatching()
        let enabled = running && preferences.enabled
        guard configuredEnabled != enabled else {
            if ready && enabled { startWatching() }
            return
        }
        configuredEnabled = enabled
        if !enabled { decision(.notEnabled) }
        let prior = lifecycle
        prior?.cancel()
        lifecycle = Task { [weak self] in
            await prior?.value
            guard let self else { return }
            ready = false
            await learning?.value
            await client.stopForTermination()
            guard !Task.isCancelled, running, preferences.enabled else { return }
            decision(.serviceStarting)
            ready = await client.start()
            guard !Task.isCancelled, running, preferences.enabled else { return }
            if ready { startWatching() } else { decision(.serviceUnavailable) }
        }
    }

    private func startWatching() {
        guard polling == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            let key = event.type == .keyDown ? Int(event.keyCode) : nil
            let timestamp = event.timestamp
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let presentedAt, timestamp < presentedAt { return }
                if key != kVK_Tab || target == nil { dismiss(reason: .inputChanged) }
            }
        }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, running, preferences.enabled else { return }
                if Permissions.isAccessibilityTrusted() {
                    if !watching { watching = true; focus.start() }
                    capture()
                } else {
                    focus.stop()
                    watching = false
                    previous = nil
                    decision(.accessibilityUnavailable)
                    dismiss()
                }
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            }
        }
    }

    private func stopWatching() {
        polling?.cancel()
        polling = nil
        refresh?.cancel()
        refresh = nil
        focus.stop()
        watching = false
        previous = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func scheduleRefresh() {
        refresh?.cancel()
        refresh = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            self?.capture()
        }
    }

    private func snapshot() -> ForkLyraTextSnapshot? {
        guard running else { decision(.stopped); return nil }
        guard preferences.enabled else { decision(.notEnabled); return nil }
        guard let focused = ForkLyraFocusObserver.focusedTarget(rejected: { decision($0) }) else { return nil }
        let app = focused.app
        let element = focused.element
        let role = ForkLyraFocusObserver.attribute(element, kAXRoleAttribute) as? String
        func reject(_ reason: ForkEvent.Reason) {
            decision(reason, bundleID: app.bundleIdentifier, role: role, pid: app.processIdentifier)
        }
        guard preferences.allows(app.bundleIdentifier) else { reject(.excludedApp); return nil }
        if let reason = Self.readRejection(element) { reject(reason); return nil }
        guard let snapshot = ForkLyraFocusObserver.snapshot(element, caretFallback: false, rejected: reject) else {
            return nil
        }
        guard snapshot.pid == app.processIdentifier else { reject(.pidMismatch); return nil }
        return snapshot
    }

    private static func readRejection(_ element: AXUIElement) -> ForkEvent.Reason? {
        guard !ForkLyraFocusObserver.isProtected(element) else { return .protected }
        let role = ForkLyraFocusObserver.attribute(element, kAXRoleAttribute) as? String ?? ""
        let editable = ForkLyraFocusObserver.attribute(element, "AXEditable") as? Bool
        guard editable != false else { return .readOnly }
        if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) { return nil }
        guard role == "AXWebArea" || role == kAXGroupRole else { return .ineligibleRole }
        if editable == true { return nil }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue ? nil : .readOnly
    }

    private func capture() {
        guard insertion == nil else { decision(.busy); return }
        guard let current = snapshot() else { previous = nil; dismiss(); return }
        guard let old = previous, CFEqual(old.element, current.element), old.pid == current.pid else {
            previous = current
            decision(.focusChanged, snapshot: current)
            dismiss()
            return
        }
        guard old.value != current.value || old.selection != current.selection else {
            if lyraIsPresenting() { dismiss() }
            else if let target, target.caretKnown != current.caretKnown || target.anchor != current.anchor
                || fallbackAnchor != (current.caretKnown ? nil : ForkAutocompleteGhostController.fallbackAnchor(for: current)) {
                dismiss(reason: .staleTarget)
            }
            return
        }
        previous = current
        dismiss()
        guard old.value != current.value else { decision(.selectionChanged, snapshot: current); return }
        if old.selection.length == 0 {
            if current.value.isEmpty {
                learn(ForkAutocompleteText.finishedWords(previous: old.value, current: old.value + " ",
                                                         location: old.value.utf16.count))
            } else {
                learn(ForkAutocompleteText.finishedWords(previous: old.value, current: current.value,
                                                         location: old.selection.location))
            }
        }
        guard current.selection.length == 0 else { decision(.selectedText, snapshot: current); return }
        guard !lyraIsPresenting() else { decision(.lyraOwnsSurface, snapshot: current); return }
        guard current.selection.location == current.value.utf16.count else {
            decision(.caretNotAtEnd, snapshot: current)
            return
        }
        guard let input = ForkAutocompleteText.input(current.value, caret: current.selection.location) else {
            decision(.unsupportedInput, snapshot: current)
            return
        }
        let version = generation
        prediction = Task { [weak self] in
            guard let self else { return }
            defer { if generation == version { prediction = nil } }
            await learning?.value
            guard !Task.isCancelled else { decision(.superseded, snapshot: current); return }
            let result = await client.request(.init(op: "predict", context: input.context, prefix: input.prefix))
            guard !Task.isCancelled, generation == version else { decision(.superseded, snapshot: current); return }
            guard !lyraIsPresenting() else { decision(.lyraOwnsSurface, snapshot: current); return }
            guard let live = snapshot() else { return }
            guard live.pid == current.pid, CFEqual(live.element, current.element),
                  live.value == current.value, live.selection == current.selection else {
                decision(.staleTarget, snapshot: live)
                return
            }
            guard let result, result.ok else { decision(.serviceUnavailable, snapshot: live); return }
            guard let confidence = result.confidence, confidence.isFinite, (0...1).contains(confidence) else {
                decision(.invalidPrediction, snapshot: live)
                return
            }
            guard confidence >= preferences.threshold else {
                decision(.lowConfidence, snapshot: live, confidencePercent: Int(confidence * 100))
                return
            }
            guard let word = result.words?.first else { decision(.noCandidate, snapshot: live); return }
            guard word.lowercased().hasPrefix(input.prefix.lowercased()), word.count > input.prefix.count else {
                decision(.invalidPrediction, snapshot: live)
                return
            }
            let rest = String(word.dropFirst(input.prefix.count))
            let kind: ForkEvent.PresentationKind = live.caretKnown ? .inlineGhost : .fallbackChip
            let anchor = live.caretKnown ? nil : ForkAutocompleteGhostController.fallbackAnchor(for: live)
            if live.caretKnown {
                guard ghost.show(rest, at: live.anchor, rejected: { decision($0, snapshot: live) }) else { return }
            } else {
                guard let anchor else { decision(.noAnchor, snapshot: live); return }
                guard ghost.showFallback(prefix: input.prefix, suffix: rest, at: anchor,
                                         rejected: { decision($0, snapshot: live) }) else { return }
            }
            target = live
            suffix = rest
            fallbackAnchor = anchor
            presentationKind = kind
            presentedAt = ProcessInfo.processInfo.systemUptime
            registerKeys()
            decision(.shown, snapshot: live, confidencePercent: Int(confidence * 100), presentationKind: kind)
        }
    }

    private func learn(_ words: [(context: [String], word: String)]) {
        guard !words.isEmpty else { return }
        let prior = learning
        learning = Task { [weak self] in
            await prior?.value
            guard let self, !Task.isCancelled else { return }
            for entry in words {
                guard !Task.isCancelled else { return }
                _ = await client.request(.init(op: "learn", context: entry.context, word: entry.word,
                                               client: identity, event: UUID().uuidString))
            }
        }
    }

    private func registerKeys() {
        for code in [kVK_Tab, kVK_Escape] {
            keys.register(id: "fork.autocomplete.\(code)",
                          shortcut: KeyShortcut(carbonKeyCode: code, carbonModifiers: 0)) { [weak self] _ in
                if code == kVK_Tab { self?.accept() } else { self?.dismiss(reason: .dismissed) }
            }
        }
    }

    private func accept() {
        guard !lyraIsPresenting() else { decision(.lyraOwnsSurface); dismiss(); return }
        guard let target, let suffix else { decision(.noCandidate); dismiss(); return }
        guard let live = snapshot() else { dismiss(); return }
        guard live.pid == target.pid, CFEqual(live.element, target.element), live.value == target.value,
              live.selection == target.selection else { decision(.staleTarget, snapshot: live); dismiss(); return }
        dismiss()
        let sink = ForkLyraTextSink(snapshot: target, range: target.selection, clipboardManager: clipboard)
        insertion = Task { [weak self] in
            guard let self else { return }
            defer { insertion = nil }
            guard !Task.isCancelled, !lyraIsPresenting() else { decision(.superseded, snapshot: target); return }
            guard let live = snapshot() else { return }
            guard live.pid == target.pid, CFEqual(live.element, target.element),
                  live.value == target.value, live.selection == target.selection else {
                decision(.staleTarget, snapshot: live)
                return
            }
            let trace = ForkTrace.Context(id: UUID(), operation: .autocomplete, clientID: nil)
            await ForkTrace.$context.withValue(trace) {
                do { try await sink.apply(suffix, to: target, range: target.selection) }
                catch { decision(.insertionFailed, snapshot: target) }
            }
            previous = snapshot()
        }
    }

    private func decision(_ reason: ForkEvent.Reason, snapshot: ForkLyraTextSnapshot? = nil,
                          bundleID: String? = nil, role: String? = nil, pid: pid_t? = nil,
                          confidencePercent: Int? = nil, presentationKind: ForkEvent.PresentationKind? = nil) {
        let process = snapshot?.pid ?? pid
        let now = ContinuousClock.now
        if reason != .shown, let last = decisions[reason], last.pid == process, now - last.time < .seconds(5) { return }
        decisions[reason] = (process, now)
        let bundle = bundleID ?? snapshot.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier }
        let trace = ForkTrace.context.flatMap { $0.operation == .autocomplete ? $0 : nil }
            ?? ForkTrace.Context(id: UUID(), operation: .autocomplete, clientID: nil)
        ForkTrace.$context.withValue(trace) {
            ForkTrace.begin(.autocomplete, category: .autocomplete, step: reason == .shown ? .offer : .decision)
                .end(reason == .shown ? .success : .skipped, fields: .init(
                    length: snapshot?.value.count, bundleID: bundle, caretKnown: snapshot?.caretKnown,
                    reason: reason, role: snapshot?.role ?? role, pid: process,
                    confidencePercent: confidencePercent, thresholdPercent: min(100, max(0, preferences.confidencePercent)),
                    presentationKind: presentationKind ?? self.presentationKind))
        }
    }

    func dismiss(reason: ForkEvent.Reason? = nil) {
        if target != nil || prediction != nil {
            if let reason { decision(reason, snapshot: target) }
            else if lyraIsPresenting() { decision(.lyraOwnsSurface, snapshot: target) }
        }
        generation += 1
        prediction?.cancel()
        prediction = nil
        ghost.dismiss()
        target = nil
        suffix = nil
        fallbackAnchor = nil
        presentationKind = nil
        presentedAt = nil
        for code in [kVK_Tab, kVK_Escape] { keys.unregister(id: "fork.autocomplete.\(code)") }
    }

    func stop() {
        running = false
        preferences.onChange = nil
        lifecycle?.cancel()
        insertion?.cancel()
        stopWatching()
        dismiss(reason: .stopped)
    }

    func stopForTermination() async {
        stop()
        await lifecycle?.value
        await learning?.value
        await insertion?.value
        await client.stopForTermination()
    }
}
