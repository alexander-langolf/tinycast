import Foundation

/// Text that came from a caller is untrusted: it is shown, never interpreted.
enum AutomationText {
    /// One line, no control or bidirectional-override characters, cut at `limit` characters.
    static func displaySafe(_ text: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                if scalar == "\n" || scalar == "\r" || scalar == "\t" { scalars.append(" ") }
            default:
                scalars.append(scalar)
            }
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    /// For the audit log: enough to recognise the argument, never the whole of it.
    static func redacted(_ text: String, limit: Int = 120) -> String {
        let flat = displaySafe(text, limit: Int.max)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…(\(flat.count) chars)"
    }
}
