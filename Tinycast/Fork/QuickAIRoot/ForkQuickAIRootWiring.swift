import Foundation

extension AppCore {
    var quickAIUsesCodex: Bool {
        aiChatCoordinator.model(for: aiChats.quickAI)?.source == .codex
    }

    func startForkQuickAIRoot() {
        forkQuickAIRootSettings.start()
        forkQuickAIRootLog.start()
        forkQuickAIRootSettings.onChange = { [weak self] in
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
