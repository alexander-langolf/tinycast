import Foundation

struct ForkClaudeSessionTranscript: Sendable {
    struct Hook: Sendable {
        let name: String
        let prompt: String?
        let permissionPrompt: Bool
        let tool: String?
    }

    enum Record: Sendable {
        case user(String, offset: UInt64)
        case assistant([AIStreamEvent], final: Bool)
        case results([AIStreamEvent])
    }

    @concurrent
    static func hooks(_ lines: [Data], sessionID: String) async throws -> [Hook] {
        try lines.compactMap { line in
            try Task.checkCancellation()
            guard let payload = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                payload["session_id"] as? String == sessionID,
                let name = payload["hook_event_name"] as? String
            else { return nil }
            return Hook(
                name: name, prompt: payload["prompt"] as? String,
                permissionPrompt: payload["notification_type"] as? String == "permission_prompt",
                tool: payload["tool_name"] as? String)
        }
    }

    @concurrent
    static func records(_ lines: [Data], sessionID: String, offset: UInt64) async throws -> [Record] {
        var consumed = offset
        return try lines.compactMap { line in
            let start = consumed
            defer { consumed += UInt64(line.count + 1) }
            try Task.checkCancellation()
            guard let payload = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                payload["isSidechain"] as? Bool != true,
                payload["isMeta"] as? Bool != true,
                let message = payload["message"] as? [String: Any]
            else { return nil }
            if let id = payload["sessionId"] as? String, id != sessionID { return nil }
            let kind = payload["type"] as? String
            let items = message["content"] as? [[String: Any]] ?? []
            if kind == "user" {
                let results = items.compactMap { item -> AIStreamEvent? in
                    guard item["type"] as? String == "tool_result",
                        let id = item["tool_use_id"] as? String
                    else { return nil }
                    return .toolResult(id: id, isError: item["is_error"] as? Bool ?? false)
                }
                if !results.isEmpty { return .results(results) }
                let text =
                    message["content"] as? String
                    ?? items.compactMap { item in
                        item["type"] as? String == "text" ? item["text"] as? String : nil
                    }.joined(separator: "\n")
                return text.isEmpty ? nil : .user(promptText(text), offset: start)
            }
            guard kind == "assistant" else { return nil }
            let events = items.compactMap { item -> AIStreamEvent? in
                switch item["type"] as? String {
                case "text": return (item["text"] as? String).map(AIStreamEvent.text)
                case "thinking": return .thinking
                case "tool_use":
                    guard let id = item["id"] as? String,
                        let name = item["name"] as? String
                    else { return nil }
                    let input = item["input"] as? [String: Any] ?? [:]
                    let data = try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys)
                    let detail = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                    let title = name + (detail.isEmpty ? "" : " · " + String(detail.prefix(120)))
                    return .toolCall(id: id, origin: "Claude Code", title: title)
                default: return nil
                }
            }
            let hasText = events.contains { if case .text = $0 { true } else { false } }
            let reason = message["stop_reason"] as? String ?? ""
            return .assistant(
                events, final: hasText && ["end_turn", "max_tokens", "stop_sequence"].contains(reason))
        }
    }

    static func promptText(_ prompt: String) -> String {
        let prefix = "\n\n<pasted_content id=\""
        guard prompt.hasPrefix(prefix) else { return prompt }
        let start = prompt.index(prompt.startIndex, offsetBy: prefix.count)
        guard let opening = prompt.range(of: "\">\n", range: start..<prompt.endIndex) else { return prompt }
        let id = prompt[start..<opening.lowerBound]
        let suffix = "\n</pasted_content id=\"\(id)\">\n"
        guard prompt.hasSuffix(suffix) else { return prompt }
        return String(prompt[opening.upperBound..<prompt.index(prompt.endIndex, offsetBy: -suffix.count)])
    }
}
