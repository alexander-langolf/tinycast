import Foundation

@main
struct ForkLyraStreamTests {
    static func main() throws {
        let configuration = AIHTTPConfiguration(provider: .openAICompatible,
            baseURL: URL(string: "http://127.0.0.1:8765/v1")!, model: "gemma-3n-e2b")
        let request = AIRequest(messages: [AIMessage(role: .user, text: "input")], maxOutputTokens: 2_048,
                                requiresCompleteText: true, localRewrite: true)
        let body = AIRequestBody.make(request, configuration: configuration)
        precondition(body["temperature"] as? Double == 0.2)
        precondition(body["max_tokens"] as? Int == 2_048 && body["cache_prompt"] as? Bool == true)
        let normal = AIRequestBody.make(AIRequest(messages: []), configuration: configuration)
        precondition(normal["temperature"] == nil && normal["cache_prompt"] == nil && normal["max_tokens"] == nil)
        let carried = request.continuing(with: request.messages, tools: [])
        precondition(carried.requiresCompleteText && carried.localRewrite)
        var complete = AIStreamDecoder(shape: .openAICompatible, requiresCompleteText: true)
        let events = try complete.feed(Data("data: {\"choices\":[{\"delta\":{\"content\":\"Reply\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8))
        precondition(complete.isTerminal && events.contains(.finished))
        for reason in ["length", "content_filter", "tool_calls"] {
            var decoder = AIStreamDecoder(shape: .openAICompatible, requiresCompleteText: true)
            do {
                _ = try decoder.feed(Data("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"\(reason)\"}]}\n\n".utf8))
                preconditionFailure("incomplete rewrite accepted")
            } catch AIProviderError.malformedResponse { }
        }
        var missing = AIStreamDecoder(shape: .openAICompatible, requiresCompleteText: true)
        do { _ = try missing.feed(Data("data: [DONE]\n\n".utf8)); preconditionFailure("missing stop reason accepted") }
        catch AIProviderError.malformedResponse { }
        var anthropic = AIStreamDecoder(shape: .anthropic, requiresCompleteText: true)
        _ = try anthropic.feed(Data("data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\ndata: {\"type\":\"message_stop\"}\n\n".utf8))
        precondition(anthropic.isTerminal)
        var truncated = AIStreamDecoder(shape: .anthropic, requiresCompleteText: true)
        do {
            _ = try truncated.feed(Data("data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"max_tokens\"}}\n\n".utf8))
            preconditionFailure("truncated Anthropic rewrite accepted")
        } catch AIProviderError.malformedResponse { }
        print("PASSED: Lyra request body and strict stream completion")
    }
}
