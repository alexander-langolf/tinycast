import Foundation

/// Where an instance's shell is, driven by its marks alone.
enum TerminalSessionPhase: Equatable, Sendable {
    /// Spawned and still reading its zsh files; a command waits for the first prompt.
    case starting
    /// At a prompt; the status is nil until a command has finished here.
    case idle(lastStatus: Int32?)
    /// A command was sent and the prompt has not come back.
    case running
    /// The shell exited; nothing more can run.
    case ended

    func applying(_ event: TerminalMarkParser.Event) -> TerminalSessionPhase {
        switch (self, event) {
        case (.ended, _), (.starting, .commandFinished), (.starting, .commandStarted):
            return self
        case (_, .commandFinished(let status)):
            return .idle(lastStatus: status)
        case (.starting, .promptReady), (.running, .promptReady):
            // A prompt with no D after a send: ⌃C at a continuation prompt ran nothing.
            return .idle(lastStatus: nil)
        case (_, .commandStarted):
            return .running
        default:
            return self
        }
    }

    var acceptsCommand: Bool {
        switch self {
        case .starting, .idle: true
        case .running, .ended: false
        }
    }
}
