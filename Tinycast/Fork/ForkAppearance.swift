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

    var monoFontFamily: String? {
        didSet {
            ForkTypography.shared.monoFamily = monoFontFamily
            if let monoFontFamily {
                defaults.set(monoFontFamily, forKey: "monoFont")
            } else {
                defaults.removeObject(forKey: "monoFont")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontFamily = defaults.string(forKey: "interfaceFont")
        monoFontFamily = defaults.string(forKey: "monoFont")
    }

    func start() {
        precondition(Self.current == nil)
        ForkTypography.shared.family = fontFamily
        ForkTypography.shared.monoFamily = monoFontFamily
        colors.publish()
        assets.publish()
        ForkSearch.setEnabled(true)
        Self.current = self
    }
}
