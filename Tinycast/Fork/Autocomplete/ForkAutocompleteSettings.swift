import Foundation
import Observation

@MainActor
@Observable
final class ForkAutocompleteSettings {
    private(set) static weak var current: ForkAutocompleteSettings?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "fork.autocomplete.enabled"); onChange?() }
    }
    var confidencePercent: Int {
        didSet { defaults.set(confidencePercent, forKey: "fork.autocomplete.confidencePercent"); onChange?() }
    }
    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: "fork.autocomplete.excludedBundleIDs"); onChange?() }
    }

    var threshold: Double { Double(min(100, max(0, confidencePercent))) / 100 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "fork.autocomplete.enabled") as? Bool ?? true
        confidencePercent = defaults.object(forKey: "fork.autocomplete.confidencePercent") as? Int ?? 50
        excludedBundleIDs = defaults.stringArray(forKey: "fork.autocomplete.excludedBundleIDs")
            ?? ["com.microsoft.VSCode", "com.apple.dt.Xcode", "dev.zed.Zed", "com.1password.1password"]
    }

    func start() { Self.current = self }

    func allows(_ bundleID: String?) -> Bool {
        guard enabled, let bundleID, bundleID != Bundle.main.bundleIdentifier,
              !["com.tinycast.app", "com.tinycast.app.dev", "com.tinycast.previews"].contains(bundleID) else { return false }
        return !excludedBundleIDs.contains(bundleID)
    }
}
