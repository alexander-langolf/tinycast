import Foundation

/// How a run ended, once it has.
struct CommandOutcome: Sendable {
    let summary: String
    /// The nudge for a failure the reader can fix, when the exit status names one.
    let hint: String?
    let succeeded: Bool
    let finishedAt: Date
}

/// One run of one command, from the moment it starts.
struct CommandRun: Identifiable, Sendable {
    let id = UUID()
    /// Which custom command this was, so the window can run it again.
    let commandID: UUID
    let name: String
    /// The shell text, shown under the name — "brew" alone says nothing about what ran.
    let commandText: String
    let symbol: String
    let startedAt: Date
    /// Everything printed so far, for copying and for a redraw from scratch.
    var log = ""
    /// One step on means the view appends this rather than walking the whole log.
    var delta = ""
    var revision = 0
    /// Bumped when the head of `log` is dropped, which is the text view's cue to redraw whole.
    var generation = 0
    /// Nil while the command is still running.
    var outcome: CommandOutcome?

    var isRunning: Bool { outcome == nil }
}
