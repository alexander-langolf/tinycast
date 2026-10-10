import SwiftUI

/// The live card: a session's state in `TerminalInstanceCard`, with ghostty's grid or the log below.
struct TerminalInstanceView: View {
    @Bindable var instance: TerminalInstance
    @Environment(TerminalInstancesCoordinator.self) private var coordinator

    private var session: TerminalSession { instance.session }

    var body: some View {
        TerminalInstanceCard(
            phase: session.phase, command: instance.lastCommand, directory: session.directory,
            startupNotice: session.startupNotice, isFullScreen: session.isFullScreen,
            isPinned: instance.isPinned, showsOutput: instance.showsOutput && session.run != nil,
            input: $instance.input,
            actions: TerminalInstanceActions(
                submit: { coordinator.submit(instance) },
                togglePinned: { coordinator.togglePinned(instance) },
                openInKitty: { coordinator.openInKitty(instance) },
                close: { coordinator.close(instance) })
        ) {
            if session.grid != nil {
                GhosttyGridView(session: session)  // FORK: libghostty prototype
            } else if let run = session.run {
                TerminalLogView(run: run)
            }
        }
    }
}
