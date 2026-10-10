import Foundation

/// `appearance.tokens`: changed tokens per component; one left out keeps its value, `null` resets it.
extension ForkThemeStore {
    func settingsFileBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(key, read: { Self.json(self.tokens) }, write: { self.apply($0, key: key) })
    }

    private static func json(_ theme: ForkTheme) -> SettingsFileJSON {
        .object(
            ForkThemeToken.Component.allCases.compactMap { component in
                let members = component.tokens.compactMap { token in
                    theme.overrides[token].map { SettingsFileJSON.Member(key: token.name, value: json($0)) }
                }
                return members.isEmpty ? nil : .init(key: component.rawValue, value: .object(members))
            })
    }

    private static func json(_ value: ForkThemeValue) -> SettingsFileJSON {
        switch value {
        case .number(let number): .number(number)
        case .flag(let flag): .bool(flag)
        case .color(let color): .string(color.hex)
        }
    }

    private static func value(_ json: SettingsFileJSON) -> ForkThemeValue? {
        if let flag = json.bool { return .flag(flag) }
        if let number = json.number { return .number(number) }
        return json.string.flatMap(ForkThemeValue.Color.init(hex:)).map(ForkThemeValue.color)
    }

    private func apply(_ json: SettingsFileJSON, key: SettingsFileKey) -> [SettingsFileIssue] {
        guard let components = json.members else { return [.invalidValue(key)] }
        var overrides = tokens.overrides
        var issues: [SettingsFileIssue] = []
        for component in components {
            guard ForkThemeToken.Component(rawValue: component.key) != nil,
                let members = component.value.members
            else {
                issues.append(.invalidEntry(key, "“\(component.key)” is not a themed component"))
                continue
            }
            for member in members {
                let path = component.key + "." + member.key
                guard let token = ForkThemeToken(rawValue: path) else {
                    issues.append(.invalidEntry(key, "unknown token “\(path)”"))
                    continue
                }
                guard member.value != .null else {
                    overrides[token] = nil
                    continue
                }
                guard let value = Self.value(member.value).flatMap(token.accepting) else {
                    issues.append(.invalidEntry(key, "“\(path)” has a value Tinycast can't use"))
                    continue
                }
                overrides[token] = value
            }
        }
        tokens.overrides = overrides
        return issues
    }
}
