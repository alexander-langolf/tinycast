import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class TerminalInstancesCoordinator {
    /// Newest first: the stack reads top to bottom in this order.
    private(set) var instances: [TerminalInstance] = []
    @ObservationIgnored private unowned let core: AppCore

    @ObservationIgnored private var isTrackingMonoFont = false
    @ObservationIgnored private var terminalLaunches: [UUID: Task<Void, Never>] = [:]

    init(core: AppCore) {
        self.core = core
    }

    /// The Monospaced font or the output tokens: every grid re-measures, tells its pty, re-heights.
    private func trackMonoFont() {
        withObservationTracking {
            _ = core.forkAppearance.monoFontFamily
            _ = ForkTheme.current
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.trackMonoFont()
                self.applyMonoFont()
            }
        }
    }

    private func applyMonoFont() {
        guard GhosttyRenderer.isEnabled else { return }
        for instance in instances { applyColors(to: instance) }
        for instance in instances {
            // FORK: file-navigator
            let layout = TerminalInstanceMetrics(
                metrics: core.settings.interfaceSize.metrics, isEditor: instance.isEditor)
            instance.session.resizeTerminal(columns: layout.columns, rows: layout.gridRows)
        }
        core.terminalInstancesPresenter.restack()
    }

    /// The palette closes and the instance takes its place; the command runs at the first prompt.
    @discardableResult
    func open(
        command: String, directory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        isEditor: Bool = false,  // FORK: file-navigator
        executable: TerminalSession.Executable? = nil, displayTitle: String? = nil,
        onClose: (@MainActor () -> Void)? = nil
    ) -> TerminalInstance? {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        // Below the palette's input bar, so the command just typed stays where the eye left it.
        let inputBar = core.settings.interfaceSize.metrics.size.compactHeight
        let anchor = core.paletteCoordinator.panelFrame.map { CGPoint(x: $0.minX, y: $0.maxY - inputBar) }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        core.paletteCoordinator.popToRootNow()
        // FORK: file-navigator
        let layout = TerminalInstanceMetrics(metrics: core.settings.interfaceSize.metrics, isEditor: isEditor)
        let instance = TerminalInstance(
            command: command, directory: directory,
            columns: layout.columns,
            rowCap: GhosttyRenderer.isEnabled ? layout.gridRows : layout.rowCap, isEditor: isEditor)
        instances.insert(instance, at: 0)
        applyColors(to: instance)
        if !isTrackingMonoFont {
            isTrackingMonoFont = true
            trackMonoFont()
        }
        core.terminalInstancesPresenter.present(instance, anchor: anchor)
        instance.session.onClose = onClose
        instance.session.start(executable: executable, command: command)
        if executable == nil { instance.begin(command) }
        instance.displayTitle = displayTitle
        return instance
    }

    /// The colour theme's terminal colours, or ghostty's own under Tinycast's look.
    private func applyColors(to instance: TerminalInstance) {
        let palette = ForkTheme.current.palette
        func packed(_ color: ForkThemeValue.Color?) -> UInt32? {
            guard let color else { return nil }
            func byte(_ channel: Double) -> UInt32 { UInt32((channel * 255).rounded()) }
            return byte(color.red) << 16 | byte(color.green) << 8 | byte(color.blue)
        }
        instance.session.grid?.applyColors(
            foreground: packed(palette?[.text]), background: packed(palette?[.terminal]),
            cursor: packed(palette?[.accent]), ansi: palette?.ansi?.compactMap(packed))
    }

    /// ↵ in the card: the next command in the same session; a typed `$ ` prefix is forgiven.
    func submit(_ instance: TerminalInstance) {
        let typed = instance.input
        let command = (TerminalCommandQuery.command(in: typed) ?? typed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, instance.session.phase.acceptsCommand else { return }
        instance.begin(command)
    }

    func close(_ instance: TerminalInstance) {
        terminalLaunches[instance.id]?.cancel()
        instance.session.terminate()
        instances.removeAll { $0.id == instance.id }
        core.terminalInstancesPresenter.dismiss(instance.id)
    }

    /// At quit: hang up every shell; the panels go with the process.
    func closeAll() {
        for task in terminalLaunches.values { task.cancel() }
        for instance in instances { instance.session.terminate() }
    }

    isolated deinit {
        for task in terminalLaunches.values { task.cancel() }
    }

    func togglePinned(_ instance: TerminalInstance) {
        instance.isPinned.toggle()
        core.terminalInstancesPresenter.applyPin(instance)
    }

    func toggleExpanded(_ instance: TerminalInstance) {
        instance.isExpanded.toggle()
    }

    // FORK: file-navigator
    func browseHere(_ instance: TerminalInstance) {
        guard instances.contains(where: { $0 === instance }) else { return }
        core.fileNavigator.show(
            input: FileNavigatorPath.directoryInput(
                instance.session.directory, home: FileManager.default.homeDirectoryForCurrentUser.path),
            origin: instance)
    }

    func openInTerminal(_ instance: TerminalInstance) {
        let id = instance.id
        guard instances.contains(where: { $0.id == id }), terminalLaunches[id] == nil else { return }
        let directory = instance.session.directory
        terminalLaunches[id] = Task { [weak self] in
            defer { self?.terminalLaunches[id] = nil }
            do {
                try await TerminalGhosttyLauncher.openShell(in: directory)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.instances.contains(where: { $0.id == id }) else {
                    return
                }
                self.core.showMessage("Couldn’t open Ghostty: \(error.localizedDescription)", tone: .danger)
            }
        }
    }

    /// The card's chords, read before its text field can swallow them.
    func handleKey(_ event: NSEvent, for instance: TerminalInstance) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key =
            ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "w":
                close(instance)
                return true
            case "o":
                openInTerminal(instance)
                return true
            case "p":
                togglePinned(instance)
                return true
            default:
                return false
            }
        }
        // FORK: file-navigator
        if flags == .control, key == "c", !instance.isEditor, instance.session.phase == .running {
            instance.session.interrupt()
            return true
        }
        if flags.isEmpty, Int(event.keyCode) == kVK_Escape {
            // FORK: libghostty prototype. A full-screen program owns Escape.
            if instance.session.phase == .running, instance.session.grid?.isAlternateScreen == true {
                return false
            }
            toggleExpanded(instance)
            return true
        }
        return false
    }
}
