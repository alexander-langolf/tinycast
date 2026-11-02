import Foundation
import Observation

@MainActor
@Observable
final class ClaudeUsageSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    var display: ClaudeUsageMenuBarDisplay {
        didSet {
            guard display != oldValue else { return }
            defaults.set(display.rawValue, forKey: "fork.claudeUsage.menuBar")
            onChange?()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        display = defaults.string(forKey: "fork.claudeUsage.menuBar")
            .flatMap(ClaudeUsageMenuBarDisplay.init(rawValue:)) ?? .disabled
    }
}

extension ClaudeUsageMenuBarDisplay: SettingsFileRawValue {}
