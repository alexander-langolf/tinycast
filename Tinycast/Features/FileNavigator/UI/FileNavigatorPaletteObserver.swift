import SwiftUI

struct FileNavigatorPaletteObserver: ViewModifier {
    @Environment(FileNavigatorCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content
            .onChange(of: palette.selection) {
                if palette.mode == .fileNavigator { coordinator.focus(palette.selection) }
            }
            .onChange(of: palette.menuOpen) {
                if palette.mode == .fileNavigator, !palette.menuOpen { coordinator.closePanel() }
            }
            .onChange(of: settings.fileSearchScopes) { refresh() }
            .onChange(of: settings.fileSearchIgnorePatterns) { refresh() }
    }

    private func refresh() {
        if palette.mode == .fileNavigator, palette.isVisible {
            coordinator.updateInput(palette.query, force: true)
        }
    }
}
