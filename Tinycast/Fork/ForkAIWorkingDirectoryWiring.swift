import Foundation

extension AppCore {
    /// Only Codex's app-server keeps a directory between turns, so only it starts again.
    func startForkAIWorkingDirectory() {
        forkAIWorkingDirectory.start()
        forkAIWorkingDirectory.onChange = { [weak self] in
            guard let subscription = self?.chatGPTSubscription, subscription.phase != .idle
            else { return }
            subscription.stop()
            subscription.refresh()
        }
    }
}

extension InstalledCLITurnRunner {
    /// Where the agent starts; `workspace` stays the private folder for Tinycast's own files.
    var cwd: URL { ForkAIWorkingDirectory.current?.url ?? workspace }
}

extension CodexAppServerClient {
    /// Read at launch and at each thread start; a change restarts the server, so the two agree.
    var cwd: URL { ForkAIWorkingDirectory.current?.url ?? workspace }
}
