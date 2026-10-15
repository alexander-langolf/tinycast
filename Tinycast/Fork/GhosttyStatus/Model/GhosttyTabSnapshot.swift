import Foundation

struct GhosttyApplicationIdentity: Hashable, Sendable {
    let processID: Int32
    let launchedAt: Date
}

struct GhosttyTabIdentity: Hashable, Sendable {
    let application: GhosttyApplicationIdentity
    let windowID: String
    let tabID: String
}

struct GhosttyTerminalIdentity: Hashable, Sendable {
    let tab: GhosttyTabIdentity
    let terminalID: String
}

enum GhosttyAgentKind: Hashable, Sendable {
    case codex
    case claude
}

struct GhosttyTerminalSnapshot: Hashable, Sendable {
    let id: String
    let workingDirectory: String?
    var foregroundProcessGroup: Int32? = nil
    var ttyDevice: UInt32? = nil
}

struct GhosttyTabSnapshot: Identifiable, Hashable, Sendable {
    let id: GhosttyTabIdentity
    let title: String?
    let terminals: [GhosttyTerminalSnapshot]
    let focusedTerminalID: String?
    var isSelected = false

    var titleText: String? {
        let text = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    var directoryName: String? {
        let directory = terminals.first(where: { $0.id == focusedTerminalID })?.workingDirectory
        guard let directory, !directory.isEmpty else { return nil }
        let name = URL(filePath: directory).lastPathComponent
        return name.isEmpty ? nil : name
    }

    var description: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let directory = terminals.first(where: { $0.id == focusedTerminalID })?.workingDirectory,
            !directory.isEmpty
        {
            let name = URL(filePath: directory).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "Terminal"
    }

    func agentKind(associations: [GhosttyTerminalIdentity: GhosttyAgentKind]) -> GhosttyAgentKind? {
        if let focusedTerminalID,
            let focused = associations[.init(tab: id, terminalID: focusedTerminalID)],
            terminals.contains(where: { $0.id == focusedTerminalID })
        {
            return focused
        }
        let kinds = Set(terminals.compactMap { associations[.init(tab: id, terminalID: $0.id)] })
        return kinds.count == 1 ? kinds.first : nil
    }
}

struct GhosttyTabInventory: Sendable {
    let application: GhosttyApplicationIdentity
    let tabs: [GhosttyTabSnapshot]
    let readAt: Date
    let capability: GhosttyAgentCapability
    let associations: [GhosttyTerminalIdentity: GhosttyAgentKind]

    init(
        application: GhosttyApplicationIdentity, tabs: [GhosttyTabSnapshot], readAt: Date,
        capability: GhosttyAgentCapability = .tabsOnly,
        associations: [GhosttyTerminalIdentity: GhosttyAgentKind] = [:]
    ) {
        self.application = application
        var seen = Set<GhosttyTabIdentity>()
        self.tabs = tabs.filter { $0.id.application == application && seen.insert($0.id).inserted }
        self.readAt = readAt
        self.capability = capability
        let terminals = Set(
            self.tabs.flatMap { tab in
                tab.terminals.map { GhosttyTerminalIdentity(tab: tab.id, terminalID: $0.id) }
            })
        self.associations =
            capability == .verifiedProcesses
            ? associations.filter { terminals.contains($0.key) } : [:]
    }
}

enum GhosttyAgentCapability: Sendable {
    case tabsOnly
    case verifiedProcesses
}

enum GhosttyStatusState: Sendable {
    case closed
    case permissionRequired
    case unavailable
    case empty
    case loaded(GhosttyTabInventory)
}

enum GhosttyStatusReconciliation {
    static func accepts(
        requestGeneration: UInt64, currentGeneration: UInt64,
        requestedApplication: GhosttyApplicationIdentity,
        currentApplication: GhosttyApplicationIdentity?
    ) -> Bool {
        requestGeneration == currentGeneration && requestedApplication == currentApplication
    }
}
