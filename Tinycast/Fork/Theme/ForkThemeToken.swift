import Foundation

/// One customisable design value. The case order is the order Settings and settings.json list them.
enum ForkThemeToken: String, CaseIterable, Sendable {
    // Spelled out, so renaming a case can never rename a key in someone's defaults or file.
    case agentCardHorizontalPadding = "agentCard.horizontalPadding"
    case agentCardVerticalPadding = "agentCard.verticalPadding"
    case agentCardGap = "agentCard.gap"
    case agentCardMargin = "agentCard.paletteMargin"
    case agentCardCornerRadius = "agentCard.cornerRadius"
    case agentCardScrimOpacity = "agentCard.scrimOpacity"
    case agentCardBorder = "agentCard.border"
    case agentCardBorderWidth = "agentCard.borderWidth"
    case agentCardBorderColor = "agentCard.borderColor"
    case agentCardTitleSize = "agentCard.titleFontSize"
    case agentCardDetailSize = "agentCard.detailFontSize"
    case agentCardTrailingSize = "agentCard.trailingFontSize"
    case agentCardDotSize = "agentCard.dotSize"
    case agentCardDotGap = "agentCard.dotGap"
    case agentCardModelColor = "agentCard.modelColor"

    case terminalBarHeight = "terminalInstance.barHeight"
    case terminalGutter = "terminalInstance.gutter"
    case terminalCornerRadius = "terminalInstance.cornerRadius"
    case terminalDivider = "terminalInstance.divider"
    case terminalDividerWidth = "terminalInstance.dividerWidth"
    case terminalGridFontSize = "terminalInstance.gridFontSize"
    case terminalOutputInsetHorizontal = "terminalInstance.outputInsetHorizontal"
    case terminalOutputInsetVertical = "terminalInstance.outputInsetVertical"

    case paletteCornerRadius = "palette.cornerRadius"
    case paletteRowPadding = "palette.rowPadding"
    case paletteRowCornerRadius = "palette.rowCornerRadius"
    case paletteSearchFieldSize = "palette.searchFieldFontSize"
    case paletteHeaderPadding = "palette.headerPadding"
    case paletteScrimDark = "palette.scrimOpacityDark"
    case paletteScrimLight = "palette.scrimOpacityLight"
    case paletteBorder = "palette.border"
    case paletteBorderWidth = "palette.borderWidth"
    case paletteBorderColor = "palette.borderColor"

    enum Component: String, CaseIterable, Sendable {
        case agentCard, terminalInstance, palette

        var title: String {
            switch self {
            case .agentCard: "Agent Card"
            case .terminalInstance: "Terminal Instance"
            case .palette: "Palette"
            }
        }

        var tokens: [ForkThemeToken] { ForkThemeToken.allCases.filter { $0.component == self } }
    }

    /// How a token is edited and what its stored value means.
    enum Kind: Equatable, Sendable {
        /// Points at the standard Interface Size; `scales` says whether larger sizes multiply it.
        case length(ClosedRange<Double>, step: Double, scales: Bool)
        case fontSize(ClosedRange<Double>, scales: Bool)
        case opacity
        case flag
        /// Unset means the adaptive ink the surface already uses, in both appearances.
        case color
    }

    var component: Component { Component(rawValue: String(rawValue.prefix { $0 != "." }))! }

    /// The key inside its component's object in settings.json.
    var name: String { String(rawValue.drop { $0 != "." }.dropFirst()) }

    var kind: Kind {
        switch self {
        case .agentCardHorizontalPadding, .terminalGutter: .length(0...48, step: 1, scales: true)
        case .terminalOutputInsetHorizontal: .length(0...48, step: 1, scales: false)
        case .agentCardVerticalPadding, .paletteRowPadding, .paletteHeaderPadding:
            .length(0...24, step: 1, scales: true)
        case .terminalOutputInsetVertical: .length(0...24, step: 1, scales: false)
        case .agentCardGap: .length(0...32, step: 1, scales: true)
        case .agentCardMargin: .length(0...48, step: 1, scales: true)
        case .agentCardCornerRadius, .terminalCornerRadius, .paletteCornerRadius:
            .length(0...40, step: 1, scales: true)
        case .paletteRowCornerRadius: .length(0...20, step: 1, scales: true)
        case .agentCardDotSize: .length(2...16, step: 1, scales: true)
        case .agentCardDotGap: .length(0...40, step: 1, scales: true)
        case .terminalBarHeight: .length(32...120, step: 1, scales: true)
        case .agentCardBorderWidth, .terminalDividerWidth, .paletteBorderWidth:
            .length(0.5...6, step: 0.5, scales: false)
        case .agentCardTitleSize, .paletteSearchFieldSize: .fontSize(9...32, scales: true)
        case .agentCardDetailSize, .agentCardTrailingSize: .fontSize(8...24, scales: true)
        case .terminalGridFontSize: .fontSize(8...24, scales: false)
        case .agentCardScrimOpacity, .paletteScrimDark, .paletteScrimLight: .opacity
        case .agentCardBorder, .terminalDivider, .paletteBorder: .flag
        case .agentCardBorderColor, .agentCardModelColor, .paletteBorderColor: .color
        }
    }

    var title: String {
        switch self {
        case .agentCardHorizontalPadding: "Horizontal padding"
        case .agentCardVerticalPadding: "Vertical padding"
        case .agentCardGap: "Gap between cards"
        case .agentCardMargin: "Margin from the palette"
        case .agentCardCornerRadius, .terminalCornerRadius, .paletteCornerRadius: "Corner radius"
        case .agentCardScrimOpacity: "Background opacity"
        case .agentCardBorder, .paletteBorder: "Border"
        case .agentCardBorderWidth, .paletteBorderWidth: "Border width"
        case .agentCardBorderColor, .paletteBorderColor: "Border colour"
        case .agentCardTitleSize: "Title font size"
        case .agentCardDetailSize: "Detail font size"
        case .agentCardTrailingSize: "Model and time font size"
        case .agentCardDotSize: "Status dot size"
        case .agentCardDotGap: "Gap after the status dot"
        case .agentCardModelColor: "Model label colour"
        case .terminalBarHeight: "Bar height"
        case .terminalGutter: "Bar gutters"
        case .terminalDivider: "Divider"
        case .terminalDividerWidth: "Divider width"
        case .terminalGridFontSize: "Output font size"
        case .terminalOutputInsetHorizontal: "Output side inset"
        case .terminalOutputInsetVertical: "Output top and bottom inset"
        case .paletteRowPadding: "Row padding"
        case .paletteRowCornerRadius: "Row corner radius"
        case .paletteSearchFieldSize: "Search field font size"
        case .paletteHeaderPadding: "Header padding"
        case .paletteScrimDark: "Scrim opacity, Dark"
        case .paletteScrimLight: "Scrim opacity, Light"
        }
    }

    /// Only where the title leaves out a consequence or a limit.
    var subtitle: String? {
        switch self {
        case .agentCardCornerRadius, .terminalCornerRadius: "Follows the palette until set."
        case .agentCardScrimOpacity: "A wash over the glass, dark in Dark and light in Light."
        case .agentCardDotGap: "Between the dot's column and the run's name."
        case .agentCardModelColor: "Unset, it dims after an agent name."
        case .terminalBarHeight: "Follows the palette's compact bar until set."
        case .terminalGridFontSize: "Uses the Monospaced font."
        case .terminalOutputInsetHorizontal, .terminalOutputInsetVertical: "Around the terminal grid."
        case .paletteRowPadding: "Above and below every list row."
        case .paletteRowCornerRadius: "Selection and hover in every list."
        case .paletteHeaderPadding: "Also sets the compact bar's height."
        case .paletteScrimDark, .paletteScrimLight: "Also the terminal card's surface."
        default: nil
        }
    }

    /// Words a search might use that the title doesn't contain.
    var keywords: [String] {
        let shared: [String]
        switch kind {
        case .length: shared = ["size", "pt", "spacing"]
        case .fontSize: shared = ["text", "type", "pt"]
        case .opacity: shared = ["alpha", "transparency", "background"]
        case .flag: shared = ["show", "hide"]
        case .color: shared = ["color", "tint"]
        }
        switch component {
        case .agentCard: return shared + ["agent", "run", "card", "claude", "codex"]
        case .terminalInstance: return shared + ["terminal", "shell", "zsh", "$"]
        case .palette: return shared + ["launcher", "window", "list"]
        }
    }
}
