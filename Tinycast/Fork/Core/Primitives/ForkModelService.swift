import Foundation
import FoundationModels

@MainActor
enum ForkModelService {
    static func complete(_ arguments: ForkModelArguments, core: AppCore) async throws -> String {
        let provider: any AIProvider
        let local = arguments.connection == "local" || arguments.connection == "lyra"
        if arguments.connection == "quickActions" {
            core.quickActionSettings.repairModel(
                against: core.aiSettings.connections, fallback: core.aiSettings.defaultModel)
            guard let selection = core.quickActionSettings.model ?? core.aiSettings.defaultModel else {
                throw AIProviderError.malformedResponse
            }
            provider = try makeProvider(selection, core: core)
        } else {
            let connection: AIConnection?
            if local {
                let preferences = core.forkLyra.preferences
                guard preferences.enabled else { throw AIProviderError.malformedResponse }
                let path = preferences.modelPath
                try await core.forkLyra.server.start(modelPath: path)
                try Task.checkCancellation()
                guard preferences.enabled, preferences.modelPath == path else { throw CancellationError() }
                connection = core.aiSettings.connection(id: preferences.connectionID)
            } else {
                connection = core.aiSettings.connections.first { $0.name == arguments.connection }
            }
            guard let connection, let model = connection.models.first else { throw AIProviderError.malformedResponse }
            provider = try makeProvider(.api(connection: connection.id, model: model, effort: "none"), core: core)
        }
        let request = AIRequest(
            instructions: arguments.instructions, messages: [AIMessage(role: .user, text: arguments.text)],
            maxOutputTokens: arguments.maxTokens, requiresCompleteText: true, localRewrite: local)
        return try await ForkTrace.step(.modelRequest, category: .workflows) {
            var output = ""
            var finished = false
            for try await event in provider.stream(request) {
                try Task.checkCancellation()
                switch event {
                case .text(let delta):
                    output += delta
                    guard output.count <= 100_000 else { throw AIProviderError.malformedResponse }
                case .finished: finished = true
                case .toolCallRequested: throw AIProviderError.malformedResponse
                default: break
                }
            }
            try Task.checkCancellation()
            let text = local ? ForkLyraText.clean(output) : output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard finished, !text.isEmpty else { throw AIProviderError.malformedResponse }
            return text
        }
    }

    private static func makeProvider(_ selection: AIModelSelection, core: AppCore) throws -> any AIProvider {
        try AIProviderFactory.make(
            selection: selection, settings: core.aiSettings,
            subscription: core.chatGPTSubscription, installedAI: core.installedAI,
            guardrails: .permissiveContentTransformations, claudeAccount: core.forkClaudeAccount)
    }

}
