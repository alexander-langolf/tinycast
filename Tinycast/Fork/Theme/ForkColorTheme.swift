import Foundation

/// A colour theme: a preset and the slots changed from it; no theme is Tinycast's adaptive look.
struct ForkColorTheme: Hashable, Sendable {
    typealias Color = ForkThemeValue.Color

    /// The ten colours a theme is written as, in theme-string order.
    enum Slot: String, CaseIterable, Sendable {
        case background, surface, text, secondaryText, accent, border, success, warning, error, terminal

        var title: String {
            switch self {
            case .background: "Window background"
            case .surface: "Surface"
            case .text: "Text"
            case .secondaryText: "Secondary text"
            case .accent: "Accent and selection"
            case .border: "Border"
            case .success: "Success"
            case .warning: "Warning"
            case .error: "Error"
            case .terminal: "Terminal background"
            }
        }
    }

    static let customID = "custom"

    /// A `ForkColorThemePreset` id, or `customID` for a theme built from a string or a file.
    var presetID: String
    /// Only the slots that differ from the preset; a custom theme derives the ones it lacks.
    var slots: [Slot: Color] = [:]
    /// Sixteen terminal colours from an imported VS Code theme; nil uses the preset's.
    var ansi: [Color]?
    var windowGradient = false

    var preset: ForkColorThemePreset? { ForkColorThemePreset.all.first { $0.id == presetID } }

    /// The theme's own slots before any contrast adjustment, derived where a custom theme has none.
    var baseSlots: [Slot: Color] {
        var base = preset?.slots ?? [:]
        base.merge(slots) { _, changed in changed }
        return ForkColorTheme.derived(from: base)
    }

    var ansiColors: [Color]? { ansi ?? preset?.ansi }

    /// Missing slots from the ones given: inks from the background, status from the system palette.
    static func derived(from given: [Slot: Color]) -> [Slot: Color] {
        let background = given[.background] ?? Color(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        let isDark = background.luminance < ForkColorPalette.darkThreshold
        let text = given[.text] ?? (isDark ? .white : .black)
        let surface = given[.surface] ?? background.mixed(with: text, amount: 0.06)
        var slots = given
        slots[.background] = background
        slots[.text] = text
        slots[.surface] = surface
        slots[.secondaryText] = given[.secondaryText] ?? text.mixed(with: background, amount: 0.4)
        slots[.accent] = given[.accent] ?? (isDark ? .hex(0x0A84FF) : .hex(0x007AFF))
        slots[.border] = given[.border] ?? background.mixed(with: text, amount: 0.2)
        slots[.success] = given[.success] ?? (isDark ? .hex(0x30D158) : .hex(0x28A745))
        slots[.warning] = given[.warning] ?? (isDark ? .hex(0xFF9F0A) : .hex(0xC77700))
        slots[.error] = given[.error] ?? (isDark ? .hex(0xFF453A) : .hex(0xD70015))
        slots[.terminal] = given[.terminal] ?? surface
        return slots
    }

    /// The comma-separated `#RRGGBB` list Slack writes, in slot order.
    var themeString: String {
        let base = baseSlots
        return Slot.allCases.compactMap { base[$0]?.hex6 }.joined(separator: ", ")
    }

    /// Fills slots in order from a pasted list; nil unless it holds at least one colour.
    init?(themeString: String) {
        let colors = themeString.split { ",; \n\t".contains($0) }.compactMap { Color(hex: String($0)) }
        guard !colors.isEmpty else { return nil }
        presetID = Self.customID
        slots = Dictionary(uniqueKeysWithValues: zip(Slot.allCases, colors))
    }

    init(presetID: String, slots: [Slot: Color] = [:], ansi: [Color]? = nil, windowGradient: Bool = false) {
        self.presetID = presetID
        self.slots = slots
        self.ansi = ansi
        self.windowGradient = windowGradient
    }

    func resolved() -> ForkColorPalette { ForkColorPalette(theme: self) }
}

extension ForkThemeValue.Color {
    static let white = Self(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = Self(red: 0, green: 0, blue: 0, alpha: 1)

    static func hex(_ rgb: UInt32) -> Self {
        Self(
            red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255, alpha: 1)
    }

    var hex6: String { String(hex.prefix(7)) }

    /// WCAG relative luminance, the measure its contrast ratio is defined on.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.039_28 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(with other: Self) -> Double {
        let (lighter, darker) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (lighter + 0.05) / (darker + 0.05)
    }

    func mixed(with other: Self, amount: Double) -> Self {
        Self(
            red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount, alpha: alpha + (other.alpha - alpha) * amount)
    }

    func withAlpha(_ value: Double) -> Self { Self(red: red, green: green, blue: blue, alpha: value) }

    /// Composited over an opaque colour, as VS Code paints a translucent token.
    func flattened(over base: Self) -> Self {
        Self(
            red: red * alpha + base.red * (1 - alpha), green: green * alpha + base.green * (1 - alpha),
            blue: blue * alpha + base.blue * (1 - alpha), alpha: 1)
    }
}

/// `{preset, slots: {slot: "#RRGGBBAA"}, ansi, windowGradient}` in defaults, JSON and backups.
extension ForkColorTheme: Codable {
    private enum CodingKeys: String, CodingKey { case preset, slots, ansi, windowGradient }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presetID = try container.decode(String.self, forKey: .preset)
        let hexes = try container.decodeIfPresent([String: String].self, forKey: .slots) ?? [:]
        slots = Self.slots(from: hexes)
        ansi = try container.decodeIfPresent([String].self, forKey: .ansi).flatMap(Self.ansi(from:))
        windowGradient = try container.decodeIfPresent(Bool.self, forKey: .windowGradient) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(presetID, forKey: .preset)
        try container.encode(slotHexes, forKey: .slots)
        try container.encodeIfPresent(ansi?.map(\.hex), forKey: .ansi)
        try container.encode(windowGradient, forKey: .windowGradient)
    }

    var slotHexes: [String: String] {
        Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value.hex) })
    }

    /// Unknown slots and unreadable colours are dropped; the rest still apply.
    static func slots(from hexes: [String: String]) -> [Slot: Color] {
        hexes.reduce(into: [:]) { slots, entry in
            guard let slot = Slot(rawValue: entry.key), let color = Color(hex: entry.value) else { return }
            slots[slot] = color
        }
    }

    /// All sixteen or none: a partial table would shift every colour after the gap.
    static func ansi(from hexes: [String]) -> [Color]? {
        let colors = hexes.compactMap(Color.init(hex:))
        return colors.count == 16 ? colors : nil
    }

    var propertyList: [String: Any] {
        var list: [String: Any] = ["preset": presetID, "slots": slotHexes, "windowGradient": windowGradient]
        if let ansi { list["ansi"] = ansi.map(\.hex) }
        return list
    }

    init?(propertyList: Any) {
        guard let list = propertyList as? [String: Any], let preset = list["preset"] as? String else {
            return nil
        }
        presetID = preset
        slots = Self.slots(from: list["slots"] as? [String: String] ?? [:])
        ansi = (list["ansi"] as? [String]).flatMap(Self.ansi(from:))
        windowGradient = list["windowGradient"] as? Bool ?? false
    }
}
