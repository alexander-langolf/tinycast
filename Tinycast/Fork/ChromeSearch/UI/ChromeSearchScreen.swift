import SwiftUI

/// The search field is the query: Google's suggestions and local history, handed to Chrome on ↵.
struct ChromeSearchScreen: PaletteScreen {
    let session: ChromeSearchSession
    let core: AppCore
    let vm: PaletteState

    private var typed: String { vm.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var coordinator: ChromeSearchCoordinator { core.chromeSearchCoordinator }

    var rows: [GoogleSearchRow] {
        GoogleSearchRow.rows(
            suggestions: session.suggestions, pages: session.pages, typed: typed,
            history: core.chromeSearchHistory.history)
    }

    private func row(at selection: Int) -> GoogleSearchRow? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    var primaryActionTitle: String {
        switch row(at: min(vm.selection, max(rows.count - 1, 0))) {
        case .website, .page: return "Open Website"
        default: return "Open in Chrome"
        }
    }

    func hasPrimaryAction(at selection: Int) -> Bool { row(at: selection) != nil }

    func hasActions(at selection: Int) -> Bool { actions(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let row = row(at: selection) else { return nil }
        switch row {
        case .typed(let text), .history(let text), .suggestion(let text):
            var items = [item("Open in Chrome", "safari", "↵") { coordinator.openResultsPage(for: text) }]
            if case .typed = row {
            } else {
                items.append(item("Use Suggestion", "arrow.right.to.line", "⇥") { vm.rewriteQuery(text) })
            }
            if case .history = row {
                items.append(
                    item("Remove from History", "trash", "⌃X") { coordinator.removeFromHistory(text) })
                items.append(item("Clear Search History", "trash", "⌃⇧X") { coordinator.clearHistory() })
            }
            return PopoverMenuContent(header: text, items: items)
        case .website(let title, let url, _):
            return websiteMenu(title: title, url: url, searchText: title)
        case .page(let title, let url, _):
            return websiteMenu(title: title, url: url, searchText: url.host() ?? title)
        }
    }

    private func websiteMenu(title: String, url: URL, searchText: String) -> PopoverMenuContent {
        PopoverMenuContent(
            header: title,
            items: [
                item("Open Website", "safari", "↵") { coordinator.openWebsite(url, named: title) },
                item("Search Google", "magnifyingglass", "⌘↵") {
                    coordinator.openResultsPage(for: searchText)
                },
                item("Use Suggestion", "arrow.right.to.line", "⇥") { vm.rewriteQuery(searchText) }
            ])
    }

    private func item(
        _ title: String, _ symbol: String, _ shortcut: String, _ action: @escaping () -> Void
    ) -> PopoverMenuItem {
        PopoverMenuItem(title: title, systemImage: symbol, shortcut: shortcut, action: action)
    }

    func activate(at selection: Int) { activate(row(at: selection)) }

    private func activate(_ row: GoogleSearchRow?) {
        switch row {
        case .typed(let text), .history(let text), .suggestion(let text):
            coordinator.openResultsPage(for: text)
        case .website(let title, let url, _), .page(let title, let url, _):
            coordinator.openWebsite(url, named: title)
        case nil: break
        }
    }

    /// ⌘↵ opens the Google results page for the row's text, as a new tab, even on a website row.
    func secondary(at selection: Int) -> Bool {
        switch row(at: selection) {
        case .typed(let text), .history(let text), .suggestion(let text), .website(let text, _, _):
            coordinator.openResultsPage(for: text)
            return true
        case .page(let title, let url, _):
            coordinator.openResultsPage(for: url.host() ?? title)
            return true
        case nil: return false
        }
    }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        switch row(at: selection) {
        case .history(let text), .suggestion(let text), .website(let text, _, _):
            vm.rewriteQuery(text)
            return true
        case .page(let title, let url, _):
            vm.rewriteQuery(url.host() ?? title)
            return true
        case .typed, nil:
            return false
        }
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let row = row(at: selection) else { return false }
        switch (shortcut, row) {
        case (.delete, .history(let text)): coordinator.removeFromHistory(text)
        case (.deleteAll, .history): coordinator.clearHistory()
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if rows.isEmpty, typed.isEmpty {
            ChromeSearchStatusView(symbol: "magnifyingglass", title: "Search Google")
        } else {
            let rows = rows
            ChromeSearchList(
                rows: rows, selectedID: row(at: selection)?.id, scroll: scroll,
                onActivate: { activate($0) })
        }
    }
}
