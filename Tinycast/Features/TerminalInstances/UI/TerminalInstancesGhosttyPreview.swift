#if DEBUG
    import SwiftUI

    /// Experiment: the real libghostty grid in the canvas, fed fixed bytes into a session that never starts.
    private struct GhosttyGridPreviewCard: View {
        @State private var session = Self.makeSession()
        @State private var input = ""
        @Environment(\.metrics) private var metrics

        private static func makeSession() -> TerminalSession {
            let layout = TerminalInstanceMetrics(metrics: InterfaceMetrics.standard)
            let session = TerminalSession(
                directory: "/Users/sasha/github/tinycast", columns: layout.columns, rowCap: layout.gridRows)
            let sample =
                "\u{1B}[1mtotal 48\u{1B}[0m\r\n"
                + "\u{1B}[34mdrwxr-xr-x\u{1B}[0m  12 sasha  staff   384 Tinycast\r\n"
                + "-rw-r--r--   1 sasha  staff  1204 AGENTS.md\r\n"
                + "\u{1B}[31merror:\u{1B}[0m cannot find 'Theme' in scope\r\n"
            session.grid?.feed(Array(sample.utf8))
            return session
        }

        var body: some View {
            let layout = TerminalInstanceMetrics(metrics: metrics)
            let rows = session.grid?.snapshot.contentRows ?? 0
            TerminalInstanceCard(
                phase: .idle(lastStatus: 0), command: "ls -la", directory: session.directory,
                startupNotice: nil, isFullScreen: false, isPinned: true, showsOutput: rows > 0,
                input: $input
            ) {
                GhosttyGridView(session: session)
            }
            .frame(
                width: layout.width,
                height: TerminalInstanceStack.cardHeight(
                    barHeight: layout.barHeight, rows: rows,
                    rowHeight: TerminalInstanceMetrics.rowHeight,
                    verticalInset: TerminalInstanceMetrics.logInset.height, maxOutput: layout.maxOutput))
        }
    }

    #Preview("Experiment · real libghostty grid") {
        TerminalInstancesPreviewData.Canvas { GhosttyGridPreviewCard() }
    }
#endif
