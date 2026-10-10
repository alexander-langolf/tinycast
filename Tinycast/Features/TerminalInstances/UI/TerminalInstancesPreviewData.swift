#if DEBUG
    import SwiftUI

    /// Sample cards and a canvas wrapper, so the terminal card can be edited visually without a shell.
    enum TerminalInstancesPreviewData {
        static let listing = [
            "total 48",
            "drwxr-xr-x  12 sasha  staff   384 10 Oct 13:02 .",
            "-rw-r--r--   1 sasha  staff  1204 10 Oct 12:58 AGENTS.md",
            "drwxr-xr-x   9 sasha  staff   288 10 Oct 12:40 Tinycast",
            "drwxr-xr-x   5 sasha  staff   160 10 Oct 12:41 Scripts",
            "-rw-r--r--   1 sasha  staff  3320 10 Oct 12:30 project.yml"
        ]
        static let buildFailure = [
            "Compiling Tinycast...",
            "error: cannot find 'Theme' in scope",
            "** BUILD FAILED **"
        ]
        static let longCommand =
            "swift build --configuration release --arch arm64 --arch x86_64 --scratch-path .build/universal --verbose"

        /// One card at the height the panel would give it: the bar, or the bar plus the sample rows.
        struct Card: View {
            var phase: TerminalSessionPhase = .idle(lastStatus: nil)
            var command = "ls -la"
            var directory = "/Users/sasha/github/tinycast"
            var startupNotice: String?
            var isFullScreen = false
            var isPinned = true
            var lines: [String] = []
            var typed = ""
            @State private var input = ""
            @Environment(\.metrics) private var metrics

            var body: some View {
                let layout = TerminalInstanceMetrics(metrics: metrics)
                TerminalInstanceCard(
                    phase: phase, command: command, directory: directory, startupNotice: startupNotice,
                    isFullScreen: isFullScreen, isPinned: isPinned, showsOutput: !lines.isEmpty,
                    input: $input
                ) {
                    OutputPlaceholder(lines: lines)
                }
                .onAppear { input = typed }
                .frame(
                    width: layout.width,
                    height: TerminalInstanceStack.cardHeight(
                        barHeight: layout.barHeight, rows: lines.count,
                        rowHeight: TerminalInstanceMetrics.rowHeight,
                        verticalInset: TerminalInstanceMetrics.logInset.height,
                        maxOutput: layout.maxOutput))
            }
        }

        /// Stands in for `GhosttyGridView`: sample output in the grid's face and inset.
        struct OutputPlaceholder: View {
            let lines: [String]

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .frame(height: TerminalInstanceMetrics.rowHeight, alignment: .leading)
                    }
                }
                .font(Font(TerminalInstanceMetrics.logFont))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, TerminalInstanceMetrics.logInset.width)
                .padding(.vertical, TerminalInstanceMetrics.logInset.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }

        /// The panel's backdrop: a desktop-like gradient behind the glass card.
        struct Canvas<Content: View>: View {
            @ViewBuilder let content: Content

            var body: some View {
                content
                    .padding(16)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            }
        }

        /// The four states stacked as the panels would be.
        struct Stack: View {
            var body: some View {
                VStack(spacing: 8) {
                    Card(phase: .running, command: "swift build", lines: buildFailure)
                    Card(phase: .idle(lastStatus: 0), command: "ls -la", lines: listing)
                    Card(phase: .idle(lastStatus: 1), command: "make", lines: buildFailure)
                    Card()
                }
            }
        }
    }

    #Preview("Idle · before the first command") {
        TerminalInstancesPreviewData.Canvas { TerminalInstancesPreviewData.Card() }
    }

    #Preview("Idle · typing a short command") {
        TerminalInstancesPreviewData.Canvas { TerminalInstancesPreviewData.Card(typed: "git status") }
    }

    #Preview("Idle · typing a long command") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(typed: TerminalInstancesPreviewData.longCommand)
        }
    }

    #Preview("Running · with output") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(
                phase: .running, command: "swift build", lines: TerminalInstancesPreviewData.buildFailure)
        }
    }

    #Preview("Finished · exit 0") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(
                phase: .idle(lastStatus: 0), lines: TerminalInstancesPreviewData.listing)
        }
    }

    #Preview("Failed · exit 2") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(
                phase: .idle(lastStatus: 2), command: "make",
                lines: TerminalInstancesPreviewData.buildFailure)
        }
    }

    #Preview("Long command") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(
                phase: .running, command: TerminalInstancesPreviewData.longCommand,
                directory: "/Users/sasha/github/some/deeply/nested/project/directory",
                lines: TerminalInstancesPreviewData.buildFailure)
        }
    }

    #Preview("Unpinned") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(
                phase: .idle(lastStatus: 0), isPinned: false, lines: TerminalInstancesPreviewData.listing)
        }
    }

    #Preview("Shell ended") {
        TerminalInstancesPreviewData.Canvas { TerminalInstancesPreviewData.Card(phase: .ended) }
    }

    #Preview("Startup notice") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(
                phase: .starting,
                startupNotice: "Shell hasn't reached a prompt: Cmd-O to open in kitty, Cmd-W to close")
        }
    }

    #Preview("Full-screen program") {
        TerminalInstancesPreviewData.Canvas {
            TerminalInstancesPreviewData.Card(phase: .running, command: "vim", isFullScreen: true)
        }
    }

    #Preview("Stack · four cards") {
        TerminalInstancesPreviewData.Canvas { TerminalInstancesPreviewData.Stack() }
    }
#endif
