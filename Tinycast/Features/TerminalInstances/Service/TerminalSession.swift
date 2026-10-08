import Foundation
import Observation

/// One instance's shell: the phase its marks report, its directory, and the current command's log.
@MainActor
@Observable
final class TerminalSession {
    private(set) var phase: TerminalSessionPhase = .starting
    private(set) var directory: String
    /// The command on screen; a new one replaces it, so the log view redraws whole.
    private(set) var run: CommandRun?
    /// A full-screen program owns the terminal until the command ends; its frames are not drawn.
    private(set) var isFullScreen = false
    /// Display rows of `run`, capped at what the card can show.
    private(set) var rows = 0
    private(set) var startupNotice: String?

    @ObservationIgnored private let columns: Int
    @ObservationIgnored private let rowCap: Int
    @ObservationIgnored private var counter: TerminalLineCounter
    @ObservationIgnored private var process: TerminalProcess?
    @ObservationIgnored private var queued: String?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var startupTimeout: Task<Void, Never>?
    @ObservationIgnored private var isTerminated = false
    /// Whether the current command reached zsh (its C mark); a ⌃C before that can strand zsh mid-line.
    @ObservationIgnored private var commandStarted = false
    @ObservationIgnored private var interruptFollowUp: Task<Void, Never>?

    /// Past this the head is dropped, as the Command Output window does.
    private static let logLimit = 256 * 1024

    init(directory: String, columns: Int, rowCap: Int) {
        self.directory = directory
        self.columns = columns
        self.rowCap = rowCap
        counter = TerminalLineCounter(columns: columns, cap: rowCap)
    }

    func start() {
        guard reader == nil else { return }
        startupTimeout = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard let self, self.phase == .starting, !self.isTerminated else { return }
            self.startupNotice =
                "Shell hasn't reached a prompt: Cmd-O to open in kitty, Cmd-W to close"
        }
        let directory = directory
        let columns = columns
        reader = Task { [weak self] in
            let spawned = await Task.detached(priority: .userInitiated) {
                TerminalProcess.spawn(directory: directory, columns: columns)
            }.value
            guard let process = spawned else {
                self?.phase = .ended
                self?.clearStartupNotice()
                return
            }
            guard let self, !self.isTerminated else {
                process.terminate()
                return
            }
            self.process = process
            for await event in process.events {
                self.handle(event)
            }
        }
    }

    /// Sent at once at a prompt, or held for the first prompt while zsh is still starting.
    func run(_ command: String) {
        guard phase.acceptsCommand, !isTerminated else { return }
        guard phase != .starting, let process else {
            queued = command
            return
        }
        send(command, to: process)
    }

    /// Only a running command: ⌃C while zsh reads its startup files would stop the shim before it installs
    /// the prompt marks, leaving the session without prompts.
    func interrupt() {
        guard !isTerminated, phase == .running else { return }
        // The phase stays running until zsh's next prompt, so the next command can't race the abort.
        process?.interrupt()
        guard !commandStarted else { return }
        // zsh was still reading the line: the first ⌃C only discards it, and no prompt follows until a
        // second one. A started command never gets the second, so its own ⌃C handling stays single.
        interruptFollowUp?.cancel()
        interruptFollowUp = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, self.phase == .running, !self.commandStarted else { return }
            self.process?.interrupt()
        }
    }

    func terminate() {
        isTerminated = true
        interruptFollowUp?.cancel()
        clearStartupNotice()
        queued = nil
        process?.terminate()
    }

    private func send(_ command: String, to process: TerminalProcess) {
        run = CommandRun(
            commandID: UUID(), name: command, commandText: command, symbol: "terminal",
            startedAt: Date())
        counter = TerminalLineCounter(columns: columns, cap: rowCap)
        rows = 0
        isFullScreen = false
        phase = .running
        commandStarted = false
        process.send(command + "\r")
    }

    private func handle(_ event: TerminalProcess.Event) {
        switch event {
        case .exited:
            phase = .ended
            clearStartupNotice()
            process = nil
        case .marks(let marks):
            for mark in marks { apply(mark) }
        }
    }

    private func apply(_ mark: TerminalMarkParser.Event) {
        phase = phase.applying(mark)
        switch mark {
        case .promptReady:
            clearStartupNotice()
            interruptFollowUp?.cancel()
            interruptFollowUp = nil
            if let command = queued, let process {
                queued = nil
                send(command, to: process)
            }
        case .commandFinished:
            isFullScreen = false
        case .workingDirectory(let path):
            directory = path
        case .alternateScreen(let entered):
            if entered, phase == .running { isFullScreen = true }
        case .output(let text):
            guard !isFullScreen else { return }
            append(text)
        case .commandStarted:
            commandStarted = true
        }
    }

    private func clearStartupNotice() {
        startupTimeout?.cancel()
        startupTimeout = nil
        startupNotice = nil
    }

    private func append(_ text: String) {
        guard var run else { return }
        run.log += text
        run.delta = text
        run.revision += 1
        if run.log.utf8.count > Self.logLimit {
            run.log = String(run.log.suffix(Self.logLimit / 2))
            run.generation += 1
        }
        self.run = run
        counter.append(text)
        if counter.rows != rows { rows = counter.rows }
    }
}
