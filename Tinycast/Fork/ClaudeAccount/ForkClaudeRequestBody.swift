import Foundation

enum ForkClaudeRequestBody {
    static let identity = "You are Claude Code, Anthropic's official CLI for Claude."
    static let cache = ["type": "ephemeral"]

    static func betas(model: ForkClaudeCatalog.Model, effort: String, title: Bool) -> [String] {
        var values = ["claude-code-20250219", "oauth-2025-04-20"]
        guard !title else { return values }
        if model.supportsMidConvoEffort {
            values += ["mid-conversation-output-config-2026-07-01", "thinking-binding-controls-2026-08-01"]
        } else if !model.forceAdaptiveThinking, effort != "none" {
            values.append("interleaved-thinking-2025-05-14")
        }
        return values
    }

    static func make(
        _ input: AIRequest, model: ForkClaudeCatalog.Model, effort: String, title: Bool = false,
        historicalEffort: (AIMessage) -> String?, thinking: [String: [JSONValue]] = [:]
    ) -> [String: Any] {
        let instructions = ([input.instructions] + input.messages.compactMap {
            $0.role == .system ? $0.text : nil
        }).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        var body: [String: Any] = [
            "model": model.id, "stream": true, "max_tokens": model.maxTokens,
            // The API refuses an empty text block, so a request without instructions sends one.
            "system": [["type": "text", "text": identity, "cache_control": cache]]
                + (instructions.isEmpty ? [] : [["type": "text", "text": instructions, "cache_control": cache]]),
            "messages": messages(
                input.messages, model: model, effort: effort, title: title,
                historicalEffort: historicalEffort, thinking: thinking)
        ]
        if input.requiresCompleteText { body["max_tokens"] = min(input.maxOutputTokens, model.maxTokens) }
        if !input.tools.isEmpty {
            body["tools"] = input.tools.enumerated().map { index, tool -> [String: Any] in
                var value: [String: Any] = [
                    "name": ForkClaudeCodeTools.toClaudeCodeName(tool.name),
                    "description": tool.description, "input_schema": tool.parameters.jsonObject,
                    "eager_input_streaming": true
                ]
                if index == input.tools.count - 1 { value["cache_control"] = cache }
                return value
            }
        }
        guard !title else { return body }
        let wireEffort = model.wireEffort(effort)
        if model.supportsMidConvoEffort {
            body["thinking"] = [
                "type": "adaptive", "display": "summarized",
                "block_binding": ["prefix_mismatch_behavior": "drop_block"]
            ]
            body["output_config"] = ["effort": "high"]
        } else if model.forceAdaptiveThinking {
            if effort != "none" {
                body["thinking"] = ["type": "adaptive", "display": "summarized"]
                body["output_config"] = ["effort": wireEffort]
            }
        } else if effort == "none" {
            body["thinking"] = ["type": "disabled"]
        } else {
            let budgets = ["minimal": 1024, "low": 2048, "medium": 8192, "high": 16384]
            let budget = budgets[wireEffort] ?? 8192
            body["thinking"] = ["type": "enabled", "budget_tokens": budget, "display": "summarized"]
            body["max_tokens"] = min(budget + model.maxTokens, model.maxTokens)
        }
        return body
    }

    private static func messages(
        _ messages: [AIMessage], model: ForkClaudeCatalog.Model, effort: String, title: Bool,
        historicalEffort: (AIMessage) -> String?, thinking: [String: [JSONValue]]
    ) -> [[String: Any]] {
        var encoded: [[String: Any]] = []
        for message in messages where message.role != .system {
            var parts: [[String: Any]] = []
            if let result = message.toolResult {
                parts = [[
                    "type": "tool_result", "tool_use_id": result.callID,
                    "content": result.content, "is_error": result.isError
                ]]
            } else {
                parts += message.images.map {
                    ["type": "image", "source": [
                        "type": "base64", "media_type": $0.mimeType,
                        "data": $0.data.base64EncodedString()
                    ]]
                }
                parts += message.documents.map {
                    ["type": "document", "source": [
                        "type": "base64", "media_type": $0.mimeType,
                        "data": $0.data.base64EncodedString()
                    ]]
                }
                // An assistant turn that thought has to open with its thinking, ahead of any text.
                for call in message.toolCalls {
                    parts += (thinking[call.id] ?? []).compactMap { $0.jsonObject as? [String: Any] }
                }
                if !message.text.isEmpty { parts.append(["type": "text", "text": message.text]) }
                for call in message.toolCalls {
                    parts.append([
                        "type": "tool_use", "id": call.id,
                        "name": ForkClaudeCodeTools.toClaudeCodeName(call.name),
                        "input": JSONValue(data: Data(call.arguments.utf8))?.jsonObject ?? [:]
                    ])
                }
            }
            guard !parts.isEmpty else { continue }
            if message.role == .assistant, model.supportsMidConvoEffort, !title {
                encoded.append(effortMessage(historicalEffort(message) ?? "medium"))
            }
            let role = message.role == .assistant ? "assistant" : "user"
            if role == "user", encoded.last?["role"] as? String == "user",
                let previous = encoded.last?["content"] as? [[String: Any]]
            {
                encoded[encoded.count - 1]["content"] = previous + parts
            } else {
                encoded.append(["role": role, "content": parts])
            }
        }
        if let index = encoded.lastIndex(where: { $0["role"] as? String == "user" }),
            var parts = encoded[index]["content"] as? [[String: Any]], !parts.isEmpty
        {
            parts[parts.count - 1]["cache_control"] = cache
            encoded[index]["content"] = parts
        }
        if model.supportsMidConvoEffort, !title { encoded.append(effortMessage(model.wireEffort(effort))) }
        return encoded
    }

    private static func effortMessage(_ effort: String) -> [String: Any] {
        ["role": "system", "content": [], "output_config": ["effort": effort]]
    }
}
