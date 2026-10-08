import AppKit
import Observation

@MainActor @Observable
final class ForkAppearance {
    private(set) static var current: ForkAppearance?
    private let defaults: UserDefaults
    var colors = ForkColors() {
        didSet { colors.publish() }
    }
    var assets = ForkAssets() {
        didSet { assets.publish() }
    }
    var fontFamily: String? {
        didSet {
            ForkTypography.shared.family = fontFamily
            if let fontFamily {
                defaults.set(fontFamily, forKey: "interfaceFont")
            } else {
                defaults.removeObject(forKey: "interfaceFont")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontFamily = defaults.string(forKey: "interfaceFont")
    }

    func start() {
        precondition(Self.current == nil)
        ForkTypography.shared.family = fontFamily
        colors.publish()
        assets.publish()
        Self.current = self
    }
}
