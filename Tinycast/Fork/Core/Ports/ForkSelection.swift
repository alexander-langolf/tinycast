import Foundation

struct ForkSelection: Sendable, Equatable {
    enum Kind: String, Sendable, CaseIterable {
        case accessibility, betterTouchTool, clipboardBorrow, kitty

        var step: ForkEvent.Step {
            switch self {
            case .accessibility: .accessibility
            case .betterTouchTool: .bttRead
            case .clipboardBorrow: .copySelection
            case .kitty: .selectionRead
            }
        }
    }

    let text: String
    let source: Kind
}
