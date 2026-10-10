import Foundation

/// Persists the tokens and colour theme under one defaults key; publishes them to `ForkThemeState`.
@MainActor
final class ForkThemeStore {
    private(set) static var current: ForkThemeStore?
    static let defaultsKey = "forkTheme"

    private let defaults: UserDefaults
    private let initial: ForkTheme

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        initial = ForkTheme(
            overrides: Self.decode(stored),
            colorTheme: stored[ForkThemeBackup.colorThemeKey].flatMap(ForkColorTheme.init(propertyList:)))
    }

    /// After `ForkAppearance.start()`, which owns the colour lookup the theme publishes into.
    func start() {
        precondition(Self.current == nil)
        ForkThemeState.shared.theme = initial
        ForkAppearance.current?.colors.theme = initial.palette
        Self.current = self
    }

    var tokens: ForkTheme {
        get { ForkThemeState.shared.theme }
        set {
            let previous = tokens
            guard newValue != previous else { return }
            ForkThemeState.shared.theme = newValue
            if newValue.palette != previous.palette { ForkAppearance.current?.colors.theme = newValue.palette }
            var stored = newValue.overrides.reduce(into: [String: Any]()) {
                $0[$1.key.rawValue] = $1.value.propertyList
            }
            stored[ForkThemeBackup.colorThemeKey] = newValue.colorTheme?.propertyList
            if stored.isEmpty {
                defaults.removeObject(forKey: Self.defaultsKey)
            } else {
                defaults.set(stored, forKey: Self.defaultsKey)
            }
        }
    }

    /// Nil returns to Tinycast's adaptive look and the Dark/Light/System choice.
    func apply(_ colorTheme: ForkColorTheme?) {
        tokens.colorTheme = colorTheme
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

    var backup: ForkThemeBackup {
        ForkThemeBackup(
            tokens: Dictionary(uniqueKeysWithValues: tokens.overrides.map { ($0.key.rawValue, $0.value) }),
            colorTheme: tokens.colorTheme)
    }

    /// A backup's set replaces the current one; unknown or unusable entries are skipped.
    func restore(_ backup: ForkThemeBackup) {
        tokens = ForkTheme(
            overrides: backup.tokens.reduce(into: [:]) { overrides, entry in
                guard let token = ForkThemeToken(rawValue: entry.key),
                    let value = token.accepting(entry.value)
                else { return }
                overrides[token] = value
            },
            colorTheme: backup.colorTheme)
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
