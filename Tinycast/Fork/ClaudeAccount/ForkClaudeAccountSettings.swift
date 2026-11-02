import Foundation

@MainActor
final class ForkClaudeAccountSettings {
    nonisolated static let connectionKey = "fork.claudeAccount.connectionID"
    private let defaults: UserDefaults
    let connectionID: UUID
    private(set) var refusedModels: Set<String>
    private(set) var refusedEfforts: [String: [String]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        connectionID = defaults.string(forKey: Self.connectionKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(connectionID.uuidString, forKey: Self.connectionKey)
        refusedModels = Set(defaults.stringArray(forKey: "fork.claudeAccount.refusedModels") ?? [])
        refusedEfforts = defaults.dictionary(forKey: "fork.claudeAccount.refusedEfforts") as? [String: [String]] ?? [:]
    }

    nonisolated static func isConnection(_ id: UUID) -> Bool {
        UserDefaults.standard.string(forKey: connectionKey) == id.uuidString
    }

    func clearRefusals() {
        refusedModels = []
        refusedEfforts = [:]
        persist()
    }

    func refuse(model: String, effort: String? = nil) {
        if let effort {
            var levels = refusedEfforts[model] ?? []
            if !levels.contains(effort) { levels.append(effort) }
            refusedEfforts[model] = levels
        } else {
            refusedModels.insert(model)
        }
        persist()
    }

    func connection() -> AIConnection {
        let models = ForkClaudeCatalog.models.filter { !refusedModels.contains($0.id) }
        let options = Dictionary(uniqueKeysWithValues: models.map { model in
            let levels = model.efforts.filter { !(refusedEfforts[model.id] ?? []).contains($0) }
            return (model.id, AIConnection.ReasoningOptions(efforts: levels, defaultEffort: "medium"))
        })
        return AIConnection(
            id: connectionID, name: String(localized: "Claude account"), provider: .anthropic,
            baseURL: "https://api.anthropic.com", models: models.map(\.id),
            visionModels: models.map(\.id), reasoningOptions: options)
    }

    var titleModel: String? {
        ForkClaudeCatalog.models.first {
            $0.id.hasPrefix("claude-haiku") && !refusedModels.contains($0.id)
        }?.id
    }

    private func persist() {
        defaults.set(refusedModels.sorted(), forKey: "fork.claudeAccount.refusedModels")
        defaults.set(refusedEfforts, forKey: "fork.claudeAccount.refusedEfforts")
    }
}
