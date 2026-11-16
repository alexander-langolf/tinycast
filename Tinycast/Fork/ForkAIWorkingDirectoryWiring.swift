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
