import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class ForkQuickAIHandoffCoordinator {
    private struct Resolution {
        let commandPath: String
        let executable: URL?
    }

    @ObservationIgnored private unowned let core: AppCore
    private var resolutions: [ForkQuickAIRootSettings.Engine: Resolution] = [:]
    private var reopenedChatID: UUID?
    private var isHandingOff = false
    @ObservationIgnored private var handoffTask: Task<Void, Never>?

    init(core: AppCore) { self.core = core }

    isolated deinit { handoffTask?.cancel() }

    private var settings: ForkQuickAIRootSettings { core.forkQuickAIRootSettings }

    var resolutionKey: [String] {
        [settings.startWorkEngine.rawValue]
            + [InstalledAIKind.claude, .codex].map { core.aiSettings.override(for: $0).commandPath }
    }

    func prepare() async {
        guard settings.startWorkEngine != .off else { return }
        for engine in [ForkQuickAIRootSettings.Engine.claude, .codex] {
            guard let kind = kind(for: engine) else { continue }
            let path = core.aiSettings.override(for: kind).commandPath
            guard resolutions[engine]?.commandPath != path else { continue }
            let executable = await ForkAIExecutableResolver.resolve(kind: kind, commandPath: path)
            guard !Task.isCancelled else { return }
            guard core.aiSettings.override(for: kind).commandPath == path else { continue }
            resolutions[engine] = Resolution(commandPath: path, executable: executable)
        }
    }

    func reopened(chatID: UUID) { reopenedChatID = chatID }

    func isReopened(chatID: UUID) -> Bool { reopenedChatID == chatID }

    func stop() {
        handoffTask?.cancel()
        handoffTask = nil
        isHandingOff = false
    }

    func actions(chat: AIChatState, composer: String) -> [PopoverMenuItem] {
        [(settings.startWorkEngine, "⌘↵"), (otherEngine, "⌃⌘↵")].compactMap { engine, shortcut in
            guard available(engine, chat: chat, composer: composer) else { return nil }
            return PopoverMenuItem(
                title: "Start Work in \(engine.title)", systemImage: "hammer", shortcut: shortcut
            ) { [weak self] in
                self?.start(engine: engine, chat: chat, composer: composer)
            }
        }
    }

    @discardableResult
    func start(other: Bool, chat: AIChatState, composer: String) -> Bool {
        start(engine: other ? otherEngine : settings.startWorkEngine, chat: chat, composer: composer)
    }

    @discardableResult
    private func start(
        engine: ForkQuickAIRootSettings.Engine, chat: AIChatState, composer: String
    ) -> Bool {
        guard available(engine, chat: chat, composer: composer),
            core.palette.mode == .ai, core.palette.query == composer,
            let kind = kind(for: engine), let executable = executable(for: engine)
        else { return false }
        let chatID = chat.session.id
        let messages = chat.session.messages
        let attachments = chat.pendingAttachments
        let defaultEngine = settings.startWorkEngine
        let commandPath = core.aiSettings.override(for: kind).commandPath
        let directory = core.forkAIWorkingDirectory.url?.path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let pending = composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && attachments.isEmpty
            ? nil
            : ChatMessage(
                role: .user, text: composer, images: attachments.compactMap(\.image),
                documents: attachments.compactMap(\.document))
        let handoff = ForkQuickAIHandoff.prompt(messages: messages, pending: pending)
        isHandingOff = true
        handoffTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isHandingOff = false
                self.handoffTask = nil
            }
            @MainActor func isCurrent() -> Bool {
                self.core.aiChats.quickAI === chat && chat.session.id == chatID
                    && chatID != self.reopenedChatID
                    && chat.session.messages == messages && chat.pendingAttachments == attachments
                    && self.core.palette.mode == .ai && self.core.palette.query == composer
                    && self.core.settings.aiEnabled && !chat.isStreaming
                    && self.settings.startWorkEngine == defaultEngine
                    && self.core.aiSettings.override(for: kind).commandPath == commandPath
                    && self.executable(for: engine) == executable
                    && (self.core.forkAIWorkingDirectory.url?.path
                        ?? FileManager.default.homeDirectoryForCurrentUser.path) == directory
            }
            do {
                let prompt: String
                if let overflow = handoff.overflow {
                    let file = try await self.core.forkQuickAIRootLog.writeHandoff(
                        chat: chatID, text: overflow)
                    prompt = handoff.text(handoffPath: file.path)
                } else { prompt = handoff.text }
                try Task.checkCancellation()
                guard isCurrent() else { return }
                if engine == .claude {
                    let handle: ForkClaudeSessionHost.Handle
                    do {
                        handle = try await self.core.forkClaudeSessionHost.start(
                            prompt: prompt, directory: URL(fileURLWithPath: directory))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard isCurrent() else { return }
                        self.core.showMessage(error.localizedDescription, tone: .danger)
                        self.launch(
                            engine: engine, executable: executable, prompt: prompt,
                            directory: directory, chatID: chatID)
                        return
                    }
                    guard let transcript = handle.transcriptPath else {
                        throw ForkClaudeSessionHost.Failure.transcriptMissing(handle.id)
                    }
                    try Task.checkCancellation()
                    guard isCurrent() else {
                        self.core.showMessage("Claude session \(handle.id) started; the Quick AI chat changed.")
                        return
                    }
                    try await self.core.forkClaudeSessionRegistry.register(
                        chatID: chatID,
                        entry: .init(
                            shortID: handle.id, sessionID: handle.sessionID,
                            transcriptPath: transcript, folder: directory))
                    try Task.checkCancellation()
                    guard isCurrent() else {
                        self.core.showMessage(
                            "Claude session \(handle.id) started; the Quick AI chat changed. Open it in Terminal.")
                        return
                    }
                    guard let provider = try self.core.forkClaudeSessions.provider(
                        chatID: chatID, initialPrompt: prompt) else { return }
                    chat.forkStartClaudeReply(pending: pending, using: provider)
                    self.core.palette.query = ""
                    self.core.quickAICoordinator.continueInChat()
                    self.core.forkQuickAIRootLog.append(.handedOff, chat: chatID, engine: .claude)
                    self.core.quickAICoordinator.startNewChat()
                } else {
                    self.launch(
                        engine: engine, executable: executable, prompt: prompt,
                        directory: directory, chatID: chatID)
                }
            } catch is CancellationError {
                return
            } catch {
                self.core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
        return true
    }

    private func launch(
        engine: ForkQuickAIRootSettings.Engine, executable: URL, prompt: String,
        directory: String, chatID: UUID
    ) {
        let command = ForkQuickAIHandoff.command(
            executable: executable.path, flags: ForkQuickAIHandoff.bypassFlags(for: engine),
            prompt: prompt)
        guard let terminal = core.terminalInstances.open(command: command, directory: directory) else {
            core.showMessage("Couldn’t open the work terminal.", tone: .danger)
            return
        }
        terminal.displayTitle = "\(engine.title) · Start Work"
        core.forkQuickAIRootLog.append(
            .handedOff, chat: chatID, engine: engine == .claude ? .claude : .codex,
            terminal: terminal.id)
        core.palette.query = ""
        core.quickAICoordinator.startNewChat()
    }

    private var otherEngine: ForkQuickAIRootSettings.Engine {
        switch settings.startWorkEngine {
        case .off: .off
        case .claude: .codex
        case .codex: .claude
        }
    }

    private func available(
        _ engine: ForkQuickAIRootSettings.Engine, chat: AIChatState, composer: String
    ) -> Bool {
        core.settings.aiEnabled && settings.startWorkEngine != .off && !isHandingOff
            && core.aiChats.quickAI === chat && chat.session.id != reopenedChatID && !chat.isStreaming
            && (chat.session.messages.contains { $0.role == .user }
                || !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && executable(for: engine) != nil
    }

    private func executable(for engine: ForkQuickAIRootSettings.Engine) -> URL? {
        guard let kind = kind(for: engine) else { return nil }
        let path = core.aiSettings.override(for: kind).commandPath
        switch InstalledAILaunch(commandPath: path).command() {
        case .executable(let url): return url
        case .missing: return nil
        case .automatic:
            guard let resolution = resolutions[engine], resolution.commandPath == path,
                let url = resolution.executable, FileManager.default.isExecutableFile(atPath: url.path)
            else { return nil }
            return url
        }
    }

    private func kind(for engine: ForkQuickAIRootSettings.Engine) -> InstalledAIKind? {
        switch engine {
        case .off: nil
        case .claude: .claude
        case .codex: .codex
        }
    }
}
