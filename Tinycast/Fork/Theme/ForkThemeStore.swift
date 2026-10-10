import Foundation

/// Persists the token overrides under one defaults key and publishes them to `ForkThemeState`.
@MainActor
final class ForkThemeStore {
    private(set) static var current: ForkThemeStore?
    static let defaultsKey = "forkTheme"

    private let defaults: UserDefaults
    private let initial: ForkTheme

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        initial = ForkTheme(overrides: Self.decode(stored))
    }

    func start() {
        precondition(Self.current == nil)
        ForkThemeState.shared.theme = initial
        Self.current = self
    }

    var tokens: ForkTheme {
        get { ForkThemeState.shared.theme }
        set {
            guard newValue != tokens else { return }
            ForkThemeState.shared.theme = newValue
            if newValue.overrides.isEmpty {
                defaults.removeObject(forKey: Self.defaultsKey)
            } else {
                defaults.set(
                    newValue.overrides.reduce(into: [String: Any]()) {
                        $0[$1.key.rawValue] = $1.value.propertyList
                    }, forKey: Self.defaultsKey)
            }
        }
    }

    /// Today's value clears the override, so an inherited default keeps following its source.
    func set(_ value: ForkThemeValue, for token: ForkThemeToken) {
        let accepted = token.accepting(value)
        tokens.overrides[token] = accepted == token.defaultValue(in: tokens) ? nil : accepted
    }

    func reset(_ token: ForkThemeToken) {
        tokens.overrides[token] = nil
    }

    func reset(_ component: ForkThemeToken.Component) {
        tokens.overrides = tokens.overrides.filter { $0.key.component != component }
    }

    /// Flat `component.token` keys, as `SettingsBackup` carries them.
    var backup: [String: ForkThemeValue] {
        Dictionary(uniqueKeysWithValues: tokens.overrides.map { ($0.key.rawValue, $0.value) })
    }

    /// A backup's set replaces the current one; unknown or unusable entries are skipped.
    func restore(_ backup: [String: ForkThemeValue]) {
        tokens.overrides = backup.reduce(into: [:]) { overrides, entry in
            guard let token = ForkThemeToken(rawValue: entry.key), let value = token.accepting(entry.value)
            else { return }
            overrides[token] = value
        }
    }

    private static func decode(_ stored: [String: Any]) -> [ForkThemeToken: ForkThemeValue] {
        stored.reduce(into: [:]) { overrides, entry in
            guard let token = ForkThemeToken(rawValue: entry.key),
                let value = ForkThemeValue(propertyList: entry.value, for: token)
            else { return }
            overrides[token] = value
        }
    }
}
