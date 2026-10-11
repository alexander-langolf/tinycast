import SwiftUI

struct FileNavigatorScreen: PaletteScreen {
    struct Row: Identifiable {
        let result: FileSearchResult?
        var id: String { result?.id ?? "file-navigator-grant-access" }
    }

    let coordinator: FileNavigatorCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [Row] {
        coordinator.needsAccess ? [Row(result: nil)] : coordinator.rows.map { Row(result: $0) }
    }

    var actsWithoutRows: Bool { true }
    var primaryActionTitle: String {
        if coordinator.needsAccess { return "Grant Access" }
        return coordinator.state.picks.isEmpty && coordinator.selected?.isDirectory == true
            ? "Browse Folder" : "Actions"
    }

    var landingSelection: Int { coordinator.state.focus }
    func hasPrimaryAction(at selection: Int) -> Bool {
        coordinator.needsAccess || !coordinator.state.picks.isEmpty || coordinator.selected != nil
    }
    func hasActions(at selection: Int) -> Bool { !coordinator.needsAccess }

    func activate(at selection: Int) {
        if coordinator.needsAccess { coordinator.grantAccess(); return }
        coordinator.focus(selection)
        coordinator.send(.enter)
        if coordinator.state.panel == .actions { openActions() }
    }

    func secondary(at selection: Int) -> Bool { false }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        coordinator.focus(selection)
        coordinator.send(backwards ? .shiftTab : .tab)
        return true
    }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard axis == .vertical else { return nil }
        coordinator.focus(selection)
        coordinator.send(delta < 0 ? .up : .down)
        return coordinator.state.focus
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        coordinator.focus(selection)
        switch shortcut {
        case .quickLook: coordinator.send(.togglePreview)
        case .openInApp: coordinator.perform(.ghosttyApp)
        case .showInFinder: coordinator.send(.subtree)
        case .copyPath: coordinator.perform(.copyPath)
        default: return false
        }
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        if coordinator.state.panel == .bookmarks {
            let folders = coordinator.state.bookmarkedFolders
            if folders.isEmpty {
                return PopoverMenuContent(
                    header: "Bookmarks & Recent",
                    items: [
                        PopoverMenuItem(
                            title: "No bookmarks or recent folders yet", systemImage: "folder",
                            isEnabled: false, action: {})
                    ])
            }
            return PopoverMenuContent(
                header: "Bookmarks & Recent",
                items: folders.map { folder in
                    PopoverMenuItem(title: folder, systemImage: "folder") {
                        coordinator.chooseFolder(folder)
                    }
                })
        }
        let targets = coordinator.targets
        let isSearch =
            switch coordinator.state.path {
            case .global: true
            case .folder: coordinator.state.subtree
            case .missing: false
            }
        return PopoverMenuContent(
            header: targets.isEmpty ? "Current Folder" : "\(targets.count) selected",
            items: FileNavigatorAction.actionsFor(targets, isSearch: isSearch).map { action in
                PopoverMenuItem(title: action.title, systemImage: action.symbol) {
                    coordinator.perform(action)
                }
            })
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(FileNavigatorView(selection: selection, scroll: scroll, openActions: openActions))
    }
}
