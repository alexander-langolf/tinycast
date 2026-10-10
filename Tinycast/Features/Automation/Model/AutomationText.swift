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

    /// For the audit log: enough to recognise the argument, never the whole of it.
    static func redacted(_ text: String, limit: Int = 120) -> String {
        let flat = displaySafe(text, limit: Int.max)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…(\(flat.count) chars)"
    }
}
