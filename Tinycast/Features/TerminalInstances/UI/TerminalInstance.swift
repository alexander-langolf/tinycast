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

    init(command: String, directory: String, columns: Int, rowCap: Int) {
        lastCommand = command
        session = TerminalSession(directory: directory, columns: columns, rowCap: rowCap)
    }

    var showsOutput: Bool { isExpanded && !session.isFullScreen && session.rows > 0 }

    func height(_ layout: TerminalInstanceMetrics) -> CGFloat {
        TerminalInstanceStack.cardHeight(
            barHeight: layout.barHeight, rows: showsOutput ? session.rows : 0,
            rowHeight: TerminalInstanceMetrics.rowHeight,
            verticalInset: TerminalInstanceMetrics.logInset.height, maxOutput: layout.maxOutput)
    }

    func begin(_ command: String) {
        lastCommand = command
        input = ""
        isExpanded = true
        session.run(command)
    }
}
