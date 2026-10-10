import Foundation

extension AppCore {
    /// The managers ask at each launch; only Codex's app-server keeps a directory between turns.
    func startForkAIWorkingDirectory() {
        let directory = forkAIWorkingDirectory
        directory.start()
        installedAI.workingDirectory = { [weak directory] in directory?.url }
        chatGPTSubscription.workingDirectory = { [weak directory] in directory?.url }
        directory.onChange = { [weak self] in
            guard let subscription = self?.chatGPTSubscription, subscription.phase != .idle
            else { return }
            subscription.stop()
            subscription.refresh()
        }
    }
}
