import Foundation

enum FileNavigatorAction: String, CaseIterable, Sendable {
    case edit, openDefault, ghostty, ghosttyApp, quickLook, copyPath, copyRelative, reveal
    case searchBelow, agent, bookmark

    var title: String {
        switch self {
        case .edit: "Edit in Fresh"
        case .openDefault: "Open with default app"
        case .ghostty: "Open Ghostty here"
        case .ghosttyApp: "Open in Ghostty app"
        case .quickLook: "Quick Look"
        case .copyPath: "Copy path(s)"
        case .copyRelative: "Copy relative path(s)"
        case .reveal: "Reveal in Finder"
        case .searchBelow: "Search below this folder"
        case .agent: "Hand to an agent"
        case .bookmark: "Bookmark folder"
        }
    }

    var symbol: String {
        switch self {
        case .edit: "pencil"
        case .openDefault: "arrow.up.forward.app"
        case .ghostty: "terminal"
        case .ghosttyApp: "macwindow"
        case .quickLook: "eye"
        case .copyPath, .copyRelative: "doc.on.clipboard"
        case .reveal, .bookmark: "folder"
        case .searchBelow: "magnifyingglass"
        case .agent: "person.crop.rectangle.stack"
        }
    }

    static func actionsFor(_ targets: [FileSearchResult]) -> [Self] {
        var actions: [Self] = []
        if targets.contains(where: { !$0.isDirectory }) { actions.append(.edit) }
        if !targets.isEmpty { actions.append(.openDefault) }
        actions += [.ghostty, .ghosttyApp]
        if !targets.isEmpty { actions += [.quickLook, .copyPath, .copyRelative, .reveal] }
        actions.append(.searchBelow)
        if !targets.isEmpty { actions.append(.agent) }
        actions.append(.bookmark)
        return actions
    }
}
