#if DEBUG
    import SwiftUI

    /// Sample runs and a canvas wrapper, so the cards can be edited visually without AppCore.
    enum AgentRunsPreviewData {
        static func run(
            _ name: String, agent: AgentRun.Kind = .subagent, state: String = "working",
            last: String? = "Read: Tinycast/Features/AgentRuns/UI/AgentRunCard.swift",
            model: String? = nil, attach: String? = "claude attach preview", minutesAgo: Int = 3
        ) -> AgentRun {
            AgentRun(
                id: name, agent: agent, name: name, cwd: "~/github/tinycast", state: state,
                startedAt: Int(Date.now.timeIntervalSince1970 * 1_000) - minutesAgo * 60_000,
                last: last, attach: attach, model: model)
        }

        static let working = run("fx architecture and spec (Explore)", model: "Opus")
        static let blocked = run(
            "Needs you: approve the migration", agent: .claude, state: "blocked",
            last: "Waiting for permission to run Scripts/lint.sh", model: "Sonnet")
        static let done = run(
            "Fix palette focus (general-purpose)", state: "done", last: "Finished; 3 files changed",
            model: "Haiku")
        static let codex = run(
            "Refactor settings schema", agent: .codex, last: "$ git diff --stat", model: "gpt-6-astra")
        static let noModel = run("Older helper, no model field", model: nil)
        static let longTitle = run(
            "A very long run title that goes on and on until it has to truncate somewhere sensible (Explore)",
            last:
                "Bash: grep -rn \"a long search pattern that also overflows the detail line\" Tinycast Tests Scripts docs",
            model: "Opus")
        static let stack = [working, blocked, codex, noModel]

        /// What the cards read from the environment: the shared metrics, over a desktop-like backdrop.
        struct Canvas<Content: View>: View {
            @ViewBuilder let content: Content

            var body: some View {
                content
                    .padding(16)
                    .frame(width: 392)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    #Preview("Card · working, Opus") {
        AgentRunsPreviewData.Canvas { AgentRunCard(run: AgentRunsPreviewData.working) {} }
    }

    #Preview("Card · blocked, Sonnet") {
        AgentRunsPreviewData.Canvas { AgentRunCard(run: AgentRunsPreviewData.blocked) {} }
    }

    #Preview("Card · done, Haiku") {
        AgentRunsPreviewData.Canvas { AgentRunCard(run: AgentRunsPreviewData.done) {} }
    }

    #Preview("Card · Codex model id") {
        AgentRunsPreviewData.Canvas { AgentRunCard(run: AgentRunsPreviewData.codex) {} }
    }

    #Preview("Card · no model") {
        AgentRunsPreviewData.Canvas { AgentRunCard(run: AgentRunsPreviewData.noModel) {} }
    }

    #Preview("Card · long title and detail") {
        AgentRunsPreviewData.Canvas { AgentRunCard(run: AgentRunsPreviewData.longTitle) {} }
    }

    #Preview("Stack · four cards") {
        AgentRunsPreviewData.Canvas {
            AgentRunsStack().environment(
                AgentRunsCoordinator(
                    monitor: AgentRunsMonitor(previewRuns: AgentRunsPreviewData.stack), showFailure: { _ in })
            )
        }
    }
#endif
