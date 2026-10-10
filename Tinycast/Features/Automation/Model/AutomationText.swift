import Foundation

/// Text that came from a caller is untrusted: it is shown, never interpreted.
enum AutomationText {
    /// One line, no control or bidirectional-override characters, cut at `limit` characters.
    static func displaySafe(_ text: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" || scalar == "\t" {
                scalars.append(" ")
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                continue
            case .format where isBidirectionalControl(scalar):
                continue
            default:
                scalars.append(scalar)
            }
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// Joiners stay, so emoji sequences survive; the controls that reorder text do not.
    private static func isBidirectionalControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }

    /// Visible tokens keep untrusted values from drawing fake dialog fields.
    static func visible(_ text: String, limit: Int) -> String {
        var shown = ""
        var count = 0
        var hidden = 0
        for scalar in text.unicodeScalars {
            let token = visibleToken(for: scalar)
            if count >= limit {
                hidden += 1
                continue
            }
            shown += token
            count += 1
        }
        return hidden == 0 ? shown : shown + "…(\(hidden) more chars)"
    }

    private static func visibleToken(for scalar: Unicode.Scalar) -> String {
        switch scalar {
        case "\n": return "␊"
        case "\r": return "␍"
        case "\t": return "␉"
        case " ": return " "
        default: break
        }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator,
            .surrogate, .privateUse, .unassigned:
            return "⟨U+\(String(scalar.value, radix: 16, uppercase: true))⟩"
        default:
            return String(scalar)
        }
    }

    /// For the audit log: enough to recognise the argument, never the whole of it.
    static func redacted(_ text: String, limit: Int = 120) -> String {
        let shown = visible(String(text.prefix(limit)), limit: Int.max)
        guard text.count > limit else { return shown }
        return shown + "…(\(text.count) chars)"
    }
}
