import SwiftUI

/// A card playground and the target Xcode's canvas previews in: the full app's static libghostty and
/// menu-bar-only scenes defeat the preview JIT. Run it (⌘R) to see the stacks in a plain window.
@main
struct TinycastPreviewsApp: App {
    var body: some Scene {
        WindowGroup("Tinycast cards") {
            TabView {
                Tab("Agent runs", systemImage: "person.2") {
                    AgentRunsPreviewData.Canvas {
                        AgentRunsStack().environment(
                            AgentRunsCoordinator(
                                monitor: AgentRunsMonitor(previewRuns: AgentRunsPreviewData.stack),
                                showFailure: { _ in }))
                    }
                }
                Tab("Terminal", systemImage: "terminal") {
                    TerminalInstancesPreviewData.Canvas { TerminalInstancesPreviewData.Stack() }
                }
            }
        }
        .windowResizability(.contentSize)
    }
}
