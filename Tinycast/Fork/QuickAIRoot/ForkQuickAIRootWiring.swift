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

    func retireQuickAIRootForNewChat() {
        guard forkQuickAIRootSettings.warmRoot else { return }
        forkQuickAIRoot.retire(reason: .newChat)
    }

    func prewarmQuickAIRoot() {
        let chat = aiChats.quickAI
        guard settings.aiEnabled, forkQuickAIRoot.canWarm, !chat.isStreaming,
            !forkQuickAIHandoff.isReopened(chatID: chat.session.id),
            let snapshot = aiChatCoordinator.forkRootSnapshot(in: chat, composer: palette.query)
        else { return }
        let chatID = chat.session.id
        forkQuickAIRoot.prewarm { [weak self, weak chat] in
            guard self != nil, chat != nil else { return }
            await snapshot.provider.turns.warmQuickAIRoot(
                for: snapshot.request, model: snapshot.provider.model,
                toolServers: snapshot.provider.toolServers
            ) { [weak self, weak chat] in
                guard let self, let chat else { return false }
                return self.settings.aiEnabled && self.aiChats.quickAI === chat
                    && chat.session.id == chatID && !chat.isStreaming
            }
        }
    }

    func startForkQuickAIRoot() {
        forkQuickAIRootSettings.start()
        forkQuickAIRootLog.start()
        chatGPTSubscription.turns.forkQuickAIRoot = forkQuickAIRoot
        chatGPTSubscription.forkKeepsRootWarm = forkQuickAIRootSettings.warmRoot
        forkQuickAIRootSettings.onChange = { [weak self] in
            guard let self else { return }
            self.forkQuickAIRoot.settingsChanged()
            self.chatGPTSubscription.forkKeepsRootWarm = self.forkQuickAIRootSettings.warmRoot
            self.forkQuickAIRootLog.settingsChanged()
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
