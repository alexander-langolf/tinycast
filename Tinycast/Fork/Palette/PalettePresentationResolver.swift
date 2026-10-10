/// The one place a palette screen's presentation is looked up, keyed on the active mode and query.
enum PalettePresentationResolver {
    @MainActor
    static func current(mode: PaletteMode, query: String) -> PalettePresentation {
        switch mode {
        case .launcher:
            if let command = TerminalCommandQuery.command(in: query) {
                return TerminalCommandScreen.presentation(for: command)
            }
            return .standard
        default:
            return .standard
        }
    }

    @MainActor
    static func current(in palette: PaletteState) -> PalettePresentation {
        current(mode: palette.mode, query: palette.query)
    }
}
