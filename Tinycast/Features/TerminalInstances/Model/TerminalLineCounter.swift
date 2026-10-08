import Foundation

/// Display rows of streamed terminal text up to a cap: the card only needs to know when it is full.
struct TerminalLineCounter: Sendable {
    let columns: Int
    let cap: Int
    private var completedRows = 0
    private var column = 0
    private var escape = EscapeState.none

    private enum EscapeState: Sendable {
        case none
        case escape
        case csi
    }

    init(columns: Int, cap: Int) {
        self.columns = max(columns, 1)
        self.cap = cap
    }

    var rows: Int { min(completedRows + (column > 0 ? 1 : 0), cap) }

    /// Wide glyphs and tabs count as one column; the cap hides the difference.
    mutating func append(_ text: String) {
        guard completedRows < cap else { return }
        for scalar in text.unicodeScalars {
            switch escape {
            case .escape:
                escape = scalar == "[" ? .csi : .none
                continue
            case .csi:
                if (0x40...0x7E).contains(scalar.value) { escape = .none }
                continue
            case .none:
                break
            }
            switch scalar {
            case "\u{1B}":
                escape = .escape
            case "\n":
                completedRows += 1
                column = 0
            case "\r":
                column = 0
            default:
                guard scalar.value >= 0x20 else { continue }
                if column == columns {
                    completedRows += 1
                    column = 0
                }
                column += 1
            }
            if completedRows >= cap { return }
        }
    }
}
