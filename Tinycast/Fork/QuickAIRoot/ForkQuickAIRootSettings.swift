import Foundation
import Observation

@MainActor @Observable
final class ForkQuickAIRootSettings {
    private(set) static var current: ForkQuickAIRootSettings?
    private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    enum Engine: String, CaseIterable, Identifiable, Sendable, SettingsFileRawValue {
        case off, claude, codex

        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Off"
            case .claude: "Claude Code"
            case .codex: "Codex"
            }
        }
    }

    enum Retention: String, CaseIterable, Identifiable, Sendable, SettingsFileRawValue {
        case hour, day, week

        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: "1 h"
            case .day: "24 h"
            case .week: "7 days"
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .hour: 3_600
            case .day: 86_400
            case .week: 604_800
            }
        }
    }

    var warmRoot: Bool {
        didSet {
            guard warmRoot != oldValue else { return }
            defaults.set(warmRoot, forKey: "quickAIWarmRoot")
            onChange?()
        }
    }

    var startWorkEngine: Engine {
        didSet {
            guard startWorkEngine != oldValue else { return }
            defaults.set(startWorkEngine.rawValue, forKey: "quickAIStartWorkEngine")
            onChange?()
        }
    }

    var retention: Retention {
        didSet {
            guard retention != oldValue else { return }
            defaults.set(retention.rawValue, forKey: "quickAIRootRetention")
            onChange?()
        }
    }

    var isEnabled: Bool { warmRoot || startWorkEngine != .off }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        warmRoot = defaults.bool(forKey: "quickAIWarmRoot")
        startWorkEngine =
            defaults.string(forKey: "quickAIStartWorkEngine")
            .flatMap(Engine.init(rawValue:)) ?? .claude
        retention =
            defaults.string(forKey: "quickAIRootRetention")
            .flatMap(Retention.init(rawValue:)) ?? .day
    }

    func start() {
        precondition(Self.current == nil)
        Self.current = self
    }

    func restore(_ backup: SettingsBackup.SettingsData) -> Int {
        var count = 0
        if let flag = backup.quickAIWarmRoot {
            warmRoot = flag
            count += 1
        }
        if let raw = backup.quickAIStartWorkEngine, let engine = Engine(rawValue: raw) {
            startWorkEngine = engine
            count += 1
        }
        if let raw = backup.quickAIRootRetention, let value = Retention(rawValue: raw) {
            retention = value
            count += 1
        }
        return count
    }
}
