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

    @ObservationIgnored private let columns: Int
    @ObservationIgnored private let rowCap: Int
    @ObservationIgnored private var counter: TerminalLineCounter
    @ObservationIgnored private var process: TerminalProcess?
    @ObservationIgnored private var queued: String?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var isTerminated = false

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
        let directory = directory
        let columns = columns
        reader = Task { [weak self] in
            let spawned = await Task.detached(priority: .userInitiated) {
                TerminalProcess.spawn(directory: directory, columns: columns)
            }.value
            guard let process = spawned else {
                self?.phase = .ended
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

    func interrupt() {
        guard phase == .running else { return }
        process?.send("\u{03}")
    }

    func terminate() {
        isTerminated = true
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
        process.send(command + "\r")
    }

    private func handle(_ event: TerminalProcess.Event) {
        switch event {
        case .exited:
            phase = .ended
            process = nil
        case .marks(let marks):
            for mark in marks { apply(mark) }
        }
    }

    private func apply(_ mark: TerminalMarkParser.Event) {
        phase = phase.applying(mark)
        switch mark {
        case .promptReady:
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
            break
        }
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
