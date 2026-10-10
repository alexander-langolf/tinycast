import Foundation

/// A token's stored value; a colour is spelled `#RRGGBBAA` everywhere it is written down.
enum ForkThemeValue: Hashable, Sendable {
    case number(Double)
    case flag(Bool)
    case color(Color)

    /// sRGB components in 0…1, so the same value reads back identically from defaults and JSON.
    struct Color: Hashable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        init(red: Double, green: Double, blue: Double, alpha: Double) {
            func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
            self.red = clamp(red)
            self.green = clamp(green)
            self.blue = clamp(blue)
            self.alpha = clamp(alpha)
        }

        /// `#RGB`, `#RGBA`, `#RRGGBB` or `#RRGGBBAA`, with or without the `#`.
        init?(hex: String) {
            let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            var digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
            if digits.count == 3 || digits.count == 4 { digits = digits.map { "\($0)\($0)" }.joined() }
            guard digits.count == 6 || digits.count == 8, let packed = UInt32(digits, radix: 16) else {
                return nil
            }
            let rgba = digits.count == 6 ? packed << 8 | 0xFF : packed
            func channel(_ shift: UInt32) -> Double { Double((rgba >> shift) & 0xFF) / 255 }
            self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
        }

        var hex: String {
            func byte(_ value: Double) -> String { String(format: "%02X", Int((value * 255).rounded())) }
            return "#" + byte(red) + byte(green) + byte(blue) + byte(alpha)
        }
    }

    var number: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var flag: Bool? {
        guard case .flag(let value) = self else { return nil }
        return value
    }

    var color: Color? {
        guard case .color(let value) = self else { return nil }
        return value
    }

    /// The property-list spelling `UserDefaults` stores.
    var propertyList: Any {
        switch self {
        case .number(let value): value
        case .flag(let value): value
        case .color(let value): value.hex
        }
    }

    /// Accepts only the shape the token's kind expects, clamped to its range.
    init?(propertyList: Any, for token: ForkThemeToken) {
        let value: ForkThemeValue
        switch propertyList {
        // `0` and `1` bridge to Bool too, so only a CFBoolean box counts as one.
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            value = .flag(number.boolValue)
        case let number as NSNumber:
            value = .number(number.doubleValue)
        case let hex as String:
            guard let color = Color(hex: hex) else { return nil }
            value = .color(color)
        default:
            return nil
        }
        guard let accepted = token.accepting(value) else { return nil }
        self = accepted
    }
}

extension ForkThemeValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = .flag(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let color = Color(hex: try container.decode(String.self)) {
            self = .color(color)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a number, flag or #RRGGBBAA colour")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value): try container.encode(value)
        case .flag(let value): try container.encode(value)
        case .color(let value): try container.encode(value.hex)
        }
    }
}

extension ForkThemeToken {
    /// A finite number inside the token's range, or nil for a flag, a colour or a non-finite value.
    func clamped(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        switch kind {
        case .length(let range, _, _), .fontSize(let range, _):
            return min(max(value, range.lowerBound), range.upperBound)
        case .opacity: return min(max(value, 0), 1)
        case .flag, .color: return nil
        }
    }

    /// The value as this token accepts it, so a decoded backup or file entry is checked once.
    func accepting(_ value: ForkThemeValue) -> ForkThemeValue? {
        switch (kind, value) {
        case (.flag, .flag), (.color, .color): value
        case (.flag, _), (.color, _): nil
        case (_, .number(let number)): clamped(number).map(ForkThemeValue.number)
        default: nil
        }
    }
}
