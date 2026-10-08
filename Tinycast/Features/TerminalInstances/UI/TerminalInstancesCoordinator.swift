import AppKit
import Carbon.HIToolbox
import Observation

/// Every terminal instance: opening one from the palette, its keys, pinning, kitty, closing.
@MainActor
@Observable
final class TerminalInstancesCoordinator {
    /// Newest first: the stack reads top to bottom in this order.
    private(set) var instances: [TerminalInstance] = []
    @ObservationIgnored private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    /// The palette closes and the instance takes its place; the command runs at the first prompt.
    func open(command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let anchor = core.paletteCoordinator.panelFrame.map { CGPoint(x: $0.minX, y: $0.maxY) }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        core.paletteCoordinator.popToRootNow()
        let layout = TerminalInstanceMetrics(metrics: core.settings.interfaceSize.metrics)
        let instance = TerminalInstance(
            command: command, directory: FileManager.default.homeDirectoryForCurrentUser.path,
            columns: layout.columns, rowCap: layout.rowCap)
        instances.insert(instance, at: 0)
        core.terminalInstancesPresenter.present(instance, anchor: anchor)
        instance.session.start()
        instance.begin(command)
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
        instance.session.terminate()
        instances.removeAll { $0.id == instance.id }
        core.terminalInstancesPresenter.dismiss(instance.id)
    }

    /// At quit: hang up every shell; the panels go with the process.
    func closeAll() {
        for instance in instances { instance.session.terminate() }
    }

    func togglePinned(_ instance: TerminalInstance) {
        instance.isPinned.toggle()
        core.terminalInstancesPresenter.applyPin(instance)
    }

    func toggleExpanded(_ instance: TerminalInstance) {
        instance.isExpanded.toggle()
    }

    func openInKitty(_ instance: TerminalInstance) {
        let directory = instance.session.directory
        Task { [weak self] in
            do {
                try await TerminalKittyLauncher.openShell(in: directory)
            } catch {
                self?.core.showMessage("Couldn’t open kitty: \(error.localizedDescription)", tone: .danger)
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
                openInKitty(instance)
                return true
            case "p":
                togglePinned(instance)
                return true
            default:
                return false
            }
        }
        if flags == .control, key == "c", instance.session.phase == .running {
            instance.session.interrupt()
            return true
        }
        if flags.isEmpty, Int(event.keyCode) == kVK_Escape {
            toggleExpanded(instance)
            return true
        }
        return false
    }
}
