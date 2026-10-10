import Foundation

/// A VS Code colour theme's `colors` read into the ten slots; the presets were built the same way.
enum ForkVSCodeTheme {
    typealias Color = ForkThemeValue.Color

    /// First present key wins. Surfaces composite over the editor background; inks keep their hue.
    private static let surfaceKeys: [ForkColorTheme.Slot: [String]] = [
        .background: ["editor.background"],
        .surface: ["sideBar.background", "panel.background", "editorWidget.background"],
        .secondaryText: ["descriptionForeground", "editorLineNumber.foreground"],
        .border: ["panel.border", "editorGroup.border", "widget.border", "contrastBorder"],
        .terminal: ["terminal.background", "panel.background"]
    ]
    private static let inkKeys: [ForkColorTheme.Slot: [String]] = [
        .text: ["editor.foreground", "foreground"],
        .accent: ["textLink.foreground", "activityBarBadge.background", "focusBorder", "button.background"],
        .success: ["terminal.ansiGreen", "gitDecoration.addedResourceForeground"],
        .warning: ["editorWarning.foreground", "terminal.ansiYellow"],
        .error: ["editorError.foreground", "terminal.ansiRed"]
    ]
    private static let ansiNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

    enum ImportError: Error, Equatable {
        case notATheme
    }

    /// A custom theme from a theme file's `colors`; the ANSI table only when all sixteen are there.
    static func theme(from data: Data) throws(ImportError) -> ForkColorTheme {
        guard let text = String(data: data, encoding: .utf8),
            let json = try? JSONSerialization.jsonObject(with: Data(stripped(text).utf8)),
            let colors = (json as? [String: Any])?["colors"] as? [String: Any]
        else { throw .notATheme }
        // Some themes write `null` to unset a key; only the string values are colours.
        let parsed = colors.compactMapValues { ($0 as? String).flatMap(Color.init(hex:)) }
        guard let background = parsed["editor.background"]?.withAlpha(1) else { throw .notATheme }
        var slots: [ForkColorTheme.Slot: Color] = [:]
        for (slot, keys) in surfaceKeys {
            if let color = first(keys, in: parsed, minimumAlpha: 0) {
                slots[slot] = color.flattened(over: background)
            }
        }
        for (slot, keys) in inkKeys {
            if let color = first(keys, in: parsed, minimumAlpha: 0.25) { slots[slot] = color.withAlpha(1) }
        }
        let terminal = slots[.terminal] ?? background
        let ansi = ["", "Bright"].flatMap { prefix in
            ansiNames.compactMap { parsed["terminal.ansi" + prefix + $0]?.flattened(over: terminal) }
        }
        return ForkColorTheme(
            presetID: ForkColorTheme.customID, slots: slots, ansi: ansi.count == 16 ? ansi : nil)
    }

    /// Fully transparent keys are skipped: VS Code uses them to switch a border off.
    private static func first(_ keys: [String], in colors: [String: Color], minimumAlpha: Double) -> Color? {
        keys.lazy.compactMap { colors[$0] }.first { $0.alpha > minimumAlpha }
    }

    /// Theme files are JSON with comments and trailing commas; strings are copied untouched.
    static func stripped(_ text: String) -> String {
        var output = ""
        var characters = Array(text)[...]
        var inString = false
        while let character = characters.popFirst() {
            if inString {
                output.append(character)
                if character == "\\", let escaped = characters.popFirst() {
                    output.append(escaped)
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch (character, characters.first) {
            case ("\"", _):
                inString = true
                output.append(character)
            case ("/", "/"):
                while let next = characters.first, next != "\n" { characters.removeFirst() }
            case ("/", "*"):
                characters.removeFirst()
                while let next = characters.popFirst() {
                    if next == "*", characters.first == "/" {
                        characters.removeFirst()
                        break
                    }
                }
            case (",", _):
                let rest = characters.drop { $0.isWhitespace }
                if let closing = rest.first, closing == "}" || closing == "]" { continue }
                output.append(character)
            default:
                output.append(character)
            }
        }
        return output
    }
}
