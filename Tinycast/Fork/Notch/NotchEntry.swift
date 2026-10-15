import Foundation

struct NotchEntry: Equatable, Sendable {
    enum Icon: Equatable, Sendable { case codex, claude, ghostty }

    let icon: Icon
    let title: String
    let subtitle: String

    static func make(state: GhosttyStatusState) -> Self {
        switch state {
        case .closed: return Self(icon: .ghostty, title: "Ghostty", subtitle: "Not running")
        case .permissionRequired:
            return Self(icon: .ghostty, title: "Ghostty", subtitle: "Automation access needed")
        case .unavailable: return Self(icon: .ghostty, title: "Ghostty", subtitle: "Unavailable")
        case .empty: return Self(icon: .ghostty, title: "Ghostty", subtitle: "No tabs")
        case .loaded(let inventory):
            guard let tab = inventory.tabs.first(where: \.isSelected) ?? inventory.tabs.first else {
                return Self(icon: .ghostty, title: "Ghostty", subtitle: "No tabs")
            }
            let kind = tab.agentKind(associations: inventory.associations)
            return Self(
                icon: kind == .codex ? .codex : kind == .claude ? .claude : .ghostty,
                title: tab.titleText ?? "Terminal", subtitle: tab.directoryName ?? "Terminal")
        }
    }
}
