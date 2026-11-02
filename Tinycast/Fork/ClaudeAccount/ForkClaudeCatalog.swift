import Foundation

enum ForkClaudeCatalog {
    struct Model: Sendable {
        let id: String
        let name: String
        let contextWindow: Int
        let maxTokens: Int
        let thinkingLevelMap: [String: String?]?
        let supportsMidConvoEffort: Bool
        let forceAdaptiveThinking: Bool

        var efforts: [String] {
            ["off", "minimal", "low", "medium", "high", "xhigh", "max"].filter { level in
                if let mapped = thinkingLevelMap?[level], mapped == nil { return false }
                return level != "xhigh" && level != "max" || thinkingLevelMap?[level] != nil
            }.map { $0 == "off" ? "none" : $0 }
        }

        func wireEffort(_ effort: String) -> String {
            let level = effort == "none" ? "off" : effort
            if let value = thinkingLevelMap?[level], let value { return value }
            return level
        }
    }

    static func model(_ id: String) -> Model? { models.first { $0.id == id } }

    static let models: [Model] = [
        Model(
            id: "claude-fable-5", name: "Claude Fable 5",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["off": nil, "xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: false, forceAdaptiveThinking: true),
        Model(
            id: "claude-fable-5-1", name: "Claude Fable 5.1",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["off": nil, "xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: true, forceAdaptiveThinking: true),
        Model(
            id: "claude-haiku-4-5", name: "Claude Haiku 4.5 (latest)",
            contextWindow: 200000, maxTokens: 64000,
            thinkingLevelMap: nil,
            supportsMidConvoEffort: false, forceAdaptiveThinking: false),
        Model(
            id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5",
            contextWindow: 200000, maxTokens: 64000,
            thinkingLevelMap: nil,
            supportsMidConvoEffort: false, forceAdaptiveThinking: false),
        Model(
            id: "claude-haiku-5-5", name: "Claude Haiku 5.5",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["off": nil, "minimal": nil, "low": "low", "medium": "medium", "high": "high", "xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: true, forceAdaptiveThinking: true),
        Model(
            id: "claude-opus-4-5", name: "Claude Opus 4.5 (latest)",
            contextWindow: 200000, maxTokens: 64000,
            thinkingLevelMap: nil,
            supportsMidConvoEffort: false, forceAdaptiveThinking: false),
        Model(
            id: "claude-opus-4-5-20251101", name: "Claude Opus 4.5",
            contextWindow: 200000, maxTokens: 64000,
            thinkingLevelMap: nil,
            supportsMidConvoEffort: false, forceAdaptiveThinking: false),
        Model(
            id: "claude-opus-4-6", name: "Claude Opus 4.6",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["max": "max"],
            supportsMidConvoEffort: false, forceAdaptiveThinking: true),
        Model(
            id: "claude-opus-4-7", name: "Claude Opus 4.7",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: false, forceAdaptiveThinking: true),
        Model(
            id: "claude-opus-4-8", name: "Claude Opus 4.8",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: false, forceAdaptiveThinking: true),
        Model(
            id: "claude-opus-5", name: "Claude Opus 5",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["off": nil, "xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: true, forceAdaptiveThinking: true),
        Model(
            id: "claude-opus-5-5", name: "Claude Opus 5.5",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["off": nil, "minimal": nil, "low": "low", "medium": "medium", "high": "high", "xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: true, forceAdaptiveThinking: true),
        Model(
            id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5 (latest)",
            contextWindow: 200000, maxTokens: 64000,
            thinkingLevelMap: nil,
            supportsMidConvoEffort: false, forceAdaptiveThinking: false),
        Model(
            id: "claude-sonnet-4-5-20250929", name: "Claude Sonnet 4.5",
            contextWindow: 200000, maxTokens: 64000,
            thinkingLevelMap: nil,
            supportsMidConvoEffort: false, forceAdaptiveThinking: false),
        Model(
            id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["max": "max"],
            supportsMidConvoEffort: false, forceAdaptiveThinking: true),
        Model(
            id: "claude-sonnet-5", name: "Claude Sonnet 5",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: false, forceAdaptiveThinking: true),
        Model(
            id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5",
            contextWindow: 1000000, maxTokens: 128000,
            thinkingLevelMap: ["off": nil, "minimal": nil, "low": "low", "medium": "medium", "high": "high", "xhigh": "xhigh", "max": "max"],
            supportsMidConvoEffort: true, forceAdaptiveThinking: true),
    ]
}
