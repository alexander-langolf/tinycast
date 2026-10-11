import Foundation

struct FileNavigatorState: Sendable {
    enum Panel: Sendable { case actions, bookmarks }
    enum Event: Sendable {
        case type(String), backspace, tab, shiftTab, up, down, enter, pick, selectAll, escape
        case hidden, togglePreview, togglePreviewExpanded, subtree, actions, bookmarks
    }

    var input: String
    var path: FileNavigatorPath
    var folder: String
    var filter = ""
    var focus = 0
    var pendingFocus: String?
    var picks: [FileSearchResult] = []
    var panel: Panel?
    var preview = true
    var previewExpanded = false
    var showHidden = false
    var subtree = false
    var bookmarks: [String] = []
    var recent: [String] = []
    var isOpen = true

    init(home: String) {
        folder = home
        input = FileNavigatorPath.directoryInput(home, home: home)
        path = .folder(home, "")
    }

    mutating func setInput(_ input: String, home: String, folders: Set<String>) {
        self.input = input
        path = FileNavigatorPath.parseInput(input, home: home, folders: folders)
        focus = 0
        pendingFocus = nil
        switch path {
        case .folder(let folder, let filter):
            if self.folder != folder {
                recent = [folder] + recent.filter { $0 != folder }.prefix(9)
                subtree = false
            }
            self.folder = folder
            self.filter = filter
        case .global: filter = ""
        case .missing: filter = "\0"
        }
    }

    mutating func reduce(_ event: Event, rows: [FileSearchResult], home: String, folders: Set<String>) {
        let row = rows.indices.contains(focus) ? rows[focus] : nil
        if panel != nil {
            if case .escape = event { panel = nil }
            return
        }
        switch event {
        case .type(let text): setInput(input + text, home: home, folders: folders)
        case .backspace:
            if !input.isEmpty { setInput(String(input.dropLast()), home: home, folders: folders) }
        case .tab:
            guard let row else { return }
            let completed =
                row.isDirectory
                ? FileNavigatorPath.directoryInput(row.id, home: home)
                : FileNavigatorPath.directoryInput(FileNavigatorPath.parent(row.id), home: home) + row.name
            setInput(completed, home: home, folders: folders)
        case .shiftTab:
            if case .global = path { return }
            if case .missing = path {
                setInput(FileNavigatorPath.directoryInput(folder, home: home), home: home, folders: folders)
                return
            }
            guard folder != "/" else { return }
            let from = folder
            setInput(
                FileNavigatorPath.directoryInput(FileNavigatorPath.parent(folder), home: home),
                home: home, folders: folders)
            pendingFocus = from
        case .up:
            pendingFocus = nil
            focus = max(0, focus - 1)
        case .down:
            pendingFocus = nil
            focus = min(max(0, rows.count - 1), focus + 1)
        case .enter:
            if !picks.isEmpty { panel = .actions; return }
            guard let row else { return }
            if row.isDirectory {
                setInput(FileNavigatorPath.directoryInput(row.id, home: home), home: home, folders: folders)
            } else {
                panel = .actions
            }
        case .pick:
            guard let row else { return }
            if picks.contains(where: { $0.id == row.id }) {
                picks.removeAll { $0.id == row.id }
            } else {
                picks.append(row)
            }
            focus = min(focus + 1, max(0, rows.count - 1))
        case .selectAll:
            let existing = Set(picks.map(\.id))
            picks.append(contentsOf: rows.filter { !existing.contains($0.id) })
        case .escape:
            if previewExpanded {
                previewExpanded = false
            } else if case .global(let words) = path, !words.isEmpty {
                setInput("~/", home: home, folders: folders)
            } else if !filter.isEmpty {
                setInput(FileNavigatorPath.directoryInput(folder, home: home), home: home, folders: folders)
            } else if !picks.isEmpty {
                picks = []
            } else {
                isOpen = false
            }
        case .hidden: showHidden.toggle(); focus = 0
        case .togglePreview:
            preview.toggle()
            if !preview { previewExpanded = false }
        case .togglePreviewExpanded:
            previewExpanded.toggle()
            if previewExpanded { preview = true }
        case .subtree:
            if case .folder = path { subtree.toggle(); focus = 0 }
        case .actions: panel = .actions
        case .bookmarks: panel = .bookmarks
        }
    }

    mutating func removeVanished(_ paths: Set<String>) {
        picks.removeAll { paths.contains($0.id) }
    }

    func targets(focused: FileSearchResult?) -> [FileSearchResult] {
        picks.isEmpty ? focused.map { [$0] } ?? [] : picks
    }

    var bookmarkedFolders: [String] { bookmarks + recent.filter { !bookmarks.contains($0) } }

    static func ranked(
        _ rows: [FileSearchResult], filter: String, shouldStop: () -> Bool = { false }
    ) -> [FileSearchResult] {
        var scored: [(row: FileSearchResult, score: Int)] = []
        let terms = ForkSearch.terms(filter, profile: .fuzzy)
        for row in rows {
            if shouldStop() { return [] }
            if filter.isEmpty { scored.append((row, 0)); continue }
            var score = 0
            var matches = true
            for term in terms {
                let hit = ForkSearch.hit(term, in: row.name)
                if term.negated {
                    if hit != nil { matches = false; break }
                } else if let hit {
                    score += hit.score
                } else {
                    matches = false; break
                }
            }
            if matches { scored.append((row, score)) }
        }
        if shouldStop() { return [] }
        return scored.sorted { left, right in
            if !filter.isEmpty, left.score != right.score { return left.score > right.score }
            if left.row.isDirectory != right.row.isDirectory { return left.row.isDirectory }
            let order = left.row.name.localizedCaseInsensitiveCompare(right.row.name)
            return order == .orderedSame ? left.row.id < right.row.id : order == .orderedAscending
        }.map(\.row)
    }
}
