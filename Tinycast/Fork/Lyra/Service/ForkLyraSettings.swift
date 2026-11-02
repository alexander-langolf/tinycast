import Foundation
import Observation

@MainActor
@Observable
final class ForkLyraSettings {
    private(set) static weak var current: ForkLyraSettings?
    let connectionID: UUID
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    var enabled: Bool { didSet { defaults.set(enabled, forKey: "fork.lyra.enabled"); onChange?() } }
    var fixEnabled: Bool { didSet { defaults.set(fixEnabled, forKey: "fork.lyra.fixEnabled"); onChange?() } }
    var modelPath: String { didSet { defaults.set(modelPath, forKey: "fork.lyra.modelPath"); onChange?() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let identifier = defaults.string(forKey: "fork.lyra.connectionID").flatMap(UUID.init(uuidString:)) ?? UUID()
        let path = defaults.string(forKey: "fork.lyra.modelPath") ?? ForkLlamaServer.defaultModel
        connectionID = identifier
        defaults.set(identifier.uuidString, forKey: "fork.lyra.connectionID")
        modelPath = path
        enabled = defaults.object(forKey: "fork.lyra.enabled") as? Bool
            ?? FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
        fixEnabled = defaults.object(forKey: "fork.lyra.fixEnabled") as? Bool ?? true
    }

    func start() { Self.current = self }

    func connection() -> AIConnection {
        AIConnection(id: connectionID, name: "Local Lyra", provider: .openAICompatible,
                     baseURL: "http://127.0.0.1:8765/v1", models: ["gemma-3n-e2b"])
    }
}
