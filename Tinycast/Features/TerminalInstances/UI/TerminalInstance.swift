import Foundation
import Observation

/// One terminal card: its session, the line being typed, and how it sits on screen.
@MainActor
@Observable
final class TerminalInstance: Identifiable {
    let id = UUID()
    let session: TerminalSession
    var input = ""
    private(set) var lastCommand: String
    var isPinned = true
    var isExpanded = true
    let isEditor: Bool  // FORK: file-navigator

    init(command: String, directory: String, columns: Int, rowCap: Int, isEditor: Bool = false) {
        self.isEditor = isEditor  // FORK: file-navigator
        lastCommand = command
        session = TerminalSession(directory: directory, columns: columns, rowCap: rowCap)
    }

    var showsOutput: Bool { isExpanded && !session.isFullScreen && session.rows > 0 }

    func height(_ layout: TerminalInstanceMetrics) -> CGFloat {
        let layout = TerminalInstanceMetrics(metrics: layout.metrics, isEditor: isEditor)  // FORK: file-navigator
        return TerminalInstanceStack.cardHeight(
            barHeight: layout.barHeight, rows: showsOutput ? session.rows : 0,
            rowHeight: TerminalInstanceMetrics.rowHeight,
            verticalInset: TerminalInstanceMetrics.logInset.height, maxOutput: layout.maxOutput,
            dividerHeight: layout.dividerHeight)
    }

    func begin(_ command: String) {
        lastCommand = command
        input = ""
        isExpanded = true
        session.run(command)
    }
}
