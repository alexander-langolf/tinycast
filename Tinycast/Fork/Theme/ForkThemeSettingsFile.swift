import Foundation

/// `appearance.tokens`: changed tokens per component; one left out keeps, `null` resets it.
extension ForkThemeStore {
    func settingsFileBinding(for key: SettingsFileKey) -> SettingsFileBinding {
        SettingsFileBinding(key, read: { Self.json(self.tokens) }, write: { self.apply($0, key: key) })
    }

    private static func json(_ theme: ForkTheme) -> SettingsFileJSON {
        var components = ForkThemeToken.Component.allCases.compactMap { component -> SettingsFileJSON.Member? in
            let members = component.tokens.compactMap { token in
                theme.overrides[token].map { SettingsFileJSON.Member(key: token.name, value: json($0)) }
            }
            return members.isEmpty ? nil : .init(key: component.rawValue, value: .object(members))
        }
        if let colorTheme = theme.colorTheme {
            components.append(.init(key: ForkThemeBackup.colorThemeKey, value: json(colorTheme)))
        }
        return .object(components)
    }

    private static func json(_ theme: ForkColorTheme) -> SettingsFileJSON {
        var members: [SettingsFileJSON.Member] = [.init(key: "preset", value: .string(theme.presetID))]
        let slots = ForkColorTheme.Slot.allCases.compactMap { slot in
            theme.slots[slot].map { SettingsFileJSON.Member(key: slot.rawValue, value: .string($0.hex)) }
        }
        members.append(.init(key: "slots", value: .object(slots)))
        if let ansi = theme.ansi { members.append(.init(key: "ansi", value: .array(ansi.map { .string($0.hex) }))) }
        members.append(.init(key: "windowGradient", value: .bool(theme.windowGradient)))
        return .object(members)
    }

    /// The preset must be known or `custom`; a bad slot colour is skipped, as a bad token is.
    private static func colorTheme(_ json: SettingsFileJSON) -> ForkColorTheme? {
        guard let preset = json["preset"]?.string,
            preset == ForkColorTheme.customID || ForkColorThemePreset.all.contains(where: { $0.id == preset })
        else { return nil }
        let hexes = (json["slots"]?.members ?? []).reduce(into: [String: String]()) {
            $0[$1.key] = $1.value.string
        }
        return ForkColorTheme(
            presetID: preset, slots: ForkColorTheme.slots(from: hexes),
            ansi: json["ansi"]?.items.flatMap { ForkColorTheme.ansi(from: $0.compactMap(\.string)) },
            windowGradient: json["windowGradient"]?.bool ?? false)
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
        var colorTheme = tokens.colorTheme
        var issues: [SettingsFileIssue] = []
        for component in components {
            if component.key == ForkThemeBackup.colorThemeKey {
                if component.value == .null {
                    colorTheme = nil
                } else if let theme = Self.colorTheme(component.value) {
                    colorTheme = theme
                } else {
                    issues.append(.invalidEntry(key, "“colorTheme” needs a known preset or “custom”"))
                }
                continue
            }
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
        tokens = ForkTheme(overrides: overrides, colorTheme: colorTheme)
        return issues
    }
}
