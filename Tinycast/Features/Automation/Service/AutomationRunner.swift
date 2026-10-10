import AppKit

/// The effects themselves. The router has already decided the call may happen.
@MainActor
final class AutomationRunner {
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    func showMessage(from label: String, text: String) {
        let text = AutomationText.displaySafe(text, limit: 120)
        let label = AutomationText.displaySafe(label, limit: 40)
        core.showMessage("\(label): \(text)", tone: .neutral)
    }

    /// Seeds the search field and never activates a row: the user still has to press return.
    func showPalette(query: String) {
        let query = AutomationText.displaySafe(query, limit: 200)
        core.paletteCoordinator.showPalette(
            mode: .launcher, restoreAnyMode: false, seeding: query.isEmpty ? nil : query)
    }
}
