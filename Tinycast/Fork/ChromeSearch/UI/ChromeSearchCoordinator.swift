import AppKit

/// The Search Google screen's actions: open it, and hand a website or the results page to Chrome.
@MainActor
final class ChromeSearchCoordinator {
    private let paletteCoordinator: PaletteCoordinator
    private let history: GoogleSearchHistoryStore

    init(paletteCoordinator: PaletteCoordinator, history: GoogleSearchHistoryStore) {
        self.paletteCoordinator = paletteCoordinator
        self.history = history
    }

    func show() { paletteCoordinator.togglePalette(mode: .googleSearch) }

    func openWebsite(_ url: URL, named title: String) {
        history.record(title)
        openInChrome(url)
    }

    func removeFromHistory(_ query: String) { history.remove(query) }

    func clearHistory() { history.clear() }

    func openResultsPage(for query: String) {
        history.record(query)
        guard
            let url = GoogleSearchURL.resultsPage(
                for: query, language: GoogleSuggestionClient.language)
        else { return }
        openInChrome(url)
    }

    /// Chrome opens a URL handed to it as a new tab in its front window.
    private func openInChrome(_ url: URL) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
        else {
            AppLauncher.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }
}
