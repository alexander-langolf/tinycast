import Foundation

// FORK: command-run
// `CommandOutcome` and `CommandRun` moved to CommandRun.swift so the preview target can compile them alone.

/// One window, reused: a second run replaces what it shows and never cancels the first.
@MainActor
@Observable
final class CommandOutputPresenter {
    /// Past this the head is dropped: the tail is where a command says how it went.
    private static let logLimit = 256 * 1024

    private(set) var run: CommandRun?

    @ObservationIgnored private let activation: ActivationPolicy
    @ObservationIgnored private let rerun: (UUID) -> Void
    @ObservationIgnored private let stop: (UUID) -> Void
    @ObservationIgnored private let openSettings: () -> Void
    @ObservationIgnored private lazy var window = AppWindowController(
        title: "Command Output", contentSize: CommandOutputView.initialSize, resizable: true,
        autosaveName: "CommandOutputWindow", activation: activation, closesOnEscape: true)

    init(
        activation: ActivationPolicy, rerun: @escaping (UUID) -> Void,
        stop: @escaping (UUID) -> Void, openSettings: @escaping () -> Void
    ) {
        self.activation = activation
        self.rerun = rerun
        self.stop = stop
        self.openSettings = openSettings
    }

    /// Opens the window on an empty, running command and returns the id the run reports against.
    @discardableResult
    func begin(commandID: UUID, name: String, commandText: String, symbol: String) -> UUID {
        let run = CommandRun(
            commandID: commandID, name: name, commandText: commandText, symbol: symbol,
            startedAt: Date())
        self.run = run
        window.show { CommandOutputView(presenter: self) }
        return run.id
    }

    func append(_ text: String, to id: UUID) {
        guard var run, run.id == id else { return }
        run.log += text
        run.delta = text
        run.revision += 1
        if run.log.utf8.count > Self.logLimit {
            run.log = String(run.log.suffix(Self.logLimit / 2))
            // The delta no longer describes the change, so the view is told to redraw instead.
            run.generation += 1
        }
        self.run = run
    }

    func finish(_ outcome: CommandOutcome, for id: UUID) {
        guard var run, run.id == id else { return }
        run.outcome = outcome
        self.run = run
    }

    // MARK: - Actions the window offers

    func runAgain() {
        guard let run else { return }
        rerun(run.commandID)
    }

    func stopRunning() {
        guard let run, run.isRunning else { return }
        stop(run.id)
    }

    func showCommandSettings() {
        openSettings()
    }

    /// Re-raise an open output window; false when none is up, so a reopen falls through.
    func focusExisting() -> Bool {
        window.focus()
    }
}
