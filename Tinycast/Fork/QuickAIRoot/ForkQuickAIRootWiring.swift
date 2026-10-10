import Foundation

extension AppCore {
    var quickAIUsesCodex: Bool {
        aiChatCoordinator.model(for: aiChats.quickAI)?.source == .codex
    }

    func makeForkQuickAIRoot() -> ForkQuickAIRoot {
        ForkQuickAIRoot(settings: forkQuickAIRootSettings, log: forkQuickAIRootLog) { [weak self] id in
            guard let self else { return false }
            return self.aiChats.quickAI.holds(id) && !self.forkQuickAIHandoff.isReopened(chatID: id)
        }
    }

    func startForkQuickAIRoot() {
        forkQuickAIRootSettings.start()
        forkQuickAIRootLog.start()
        chatGPTSubscription.turns.forkQuickAIRoot = forkQuickAIRoot
        forkQuickAIRootSettings.onChange = { [weak self] in
            self?.forkQuickAIRoot.settingsChanged()
            self?.forkQuickAIRootLog.settingsChanged()
        }
    }
}

extension SettingsBackup.SettingsData {
    @MainActor
    mutating func gatherQuickAIRoot(from settings: ForkQuickAIRootSettings) {
        quickAIWarmRoot = settings.warmRoot
        quickAIStartWorkEngine = settings.startWorkEngine.rawValue
        quickAIRootRetention = settings.retention.rawValue
    }
}
