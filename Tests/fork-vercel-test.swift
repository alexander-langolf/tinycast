import Foundation

@main
struct ForkVercelTests {
    static func main() async throws {
        let model = "anthropic/claude-haiku-5.5"
        let connection = AIConnection(
            provider: .openAICompatible, baseURL: "https://ai-gateway.vercel.sh/v1",
            models: [model], reasoningOptions: [model: .init(efforts: ["none"], defaultEffort: "none")])
        precondition(!connection.takesThinkingField)
        precondition(connection.offeredEffort("none", for: model) == "none")
        let configuration = AIHTTPConfiguration(
            provider: connection.provider, baseURL: URL(string: connection.baseURL)!, model: model,
            effort: "none", disablesThinking: connection.takesThinkingField)
        let request = AIRequest(
            instructions: "Translate to English. Reply with only the translation.",
            messages: [AIMessage(role: .user, text: "Bonjour.")], maxOutputTokens: 128,
            requiresCompleteText: true)
        let body = AIRequestBody.make(request, configuration: configuration)
        precondition(body["reasoning_effort"] as? String == "none")
        precondition(body["thinking"] == nil && body["cache_prompt"] == nil)
        guard ProcessInfo.processInfo.environment["TINYCAST_TEST_VERCEL"] == "1" else {
            print("PASSED: Vercel request routing; live check requires TINYCAST_TEST_VERCEL=1")
            return
        }
        let store = KeychainSecretStore(scope: "ai-api-keys", bundleIdentifier: "com.tinycast.app.dev")
        let id = UUID(uuidString: "86C3B84F-B072-4E37-A4F6-2A3A4BA128E7")!
        guard let key = try store.secret(for: id), !key.isEmpty else {
            throw AIProviderError.malformedResponse
        }
        let provider = HTTPAIProvider(configuration: configuration, apiKey: key)
        var text = ""
        var finished = false
        for try await event in provider.stream(request) {
            switch event {
            case .text(let piece): text += piece
            case .finished: finished = true
            default: break
            }
        }
        precondition(finished && text.lowercased().contains("hello"))
        print("PASSED: shipped HTTP provider streamed a complete Haiku translation through Vercel")
    }
}
