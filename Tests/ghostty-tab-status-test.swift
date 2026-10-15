import Foundation

@main
struct GhosttyTabStatusTest {
    static func main() {
        detection()
        capabilities()
        let application = GhosttyApplicationIdentity(
            processID: 42, launchedAt: Date(timeIntervalSince1970: 1))
        let identity = GhosttyTabIdentity(application: application, windowID: "w1", tabID: "t1")
        let tab = GhosttyTabSnapshot(
            id: identity, title: "  ",
            terminals: [
                .init(id: "shell", workingDirectory: "/work/tinycast"),
                .init(id: "agent", workingDirectory: "/work/tinycast")
            ],
            focusedTerminalID: "shell")
        precondition(tab.description == "tinycast")
        let shell = GhosttyTerminalIdentity(tab: identity, terminalID: "shell")
        let agent = GhosttyTerminalIdentity(tab: identity, terminalID: "agent")
        precondition(tab.agentKind(associations: [:]) == nil)
        precondition(tab.agentKind(associations: [agent: .codex]) == .codex)
        precondition(tab.agentKind(associations: [shell: .claude, agent: .codex]) == .claude)
        let conflict = GhosttyTabSnapshot(
            id: identity, title: "Codex is here", terminals: tab.terminals,
            focusedTerminalID: nil)
        precondition(conflict.agentKind(associations: [shell: .claude, agent: .codex]) == nil)
        precondition(conflict.agentKind(associations: [:]) == nil)
        let otherTab = GhosttyTabSnapshot(
            id: .init(application: application, windowID: "w1", tabID: "t2"),
            title: nil, terminals: [.init(id: "agent", workingDirectory: nil)],
            focusedTerminalID: "agent")
        precondition(otherTab.agentKind(associations: [agent: .codex]) == nil)
        let inventory = GhosttyTabInventory(application: application, tabs: [tab, tab], readAt: .now)
        precondition(inventory.tabs.count == 1)
        precondition(
            GhosttyStatusReconciliation.accepts(
                requestGeneration: 2, currentGeneration: 2,
                requestedApplication: application, currentApplication: application))
        precondition(
            !GhosttyStatusReconciliation.accepts(
                requestGeneration: 1, currentGeneration: 2,
                requestedApplication: application, currentApplication: application))
        precondition(
            !GhosttyStatusReconciliation.accepts(
                requestGeneration: 2, currentGeneration: 2,
                requestedApplication: application,
                currentApplication: .init(processID: 42, launchedAt: Date(timeIntervalSince1970: 2))))
    }

    static func detection() {
        let app = GhosttyApplicationIdentity(processID: 1, launchedAt: .distantPast)
        let tabID = GhosttyTabIdentity(application: app, windowID: "window", tabID: "tab")
        let tab = GhosttyTabSnapshot(
            id: tabID, title: "Claude and Codex",
            terminals: [
                .init(id: "codex", workingDirectory: nil, foregroundProcessGroup: 100, ttyDevice: 10),
                .init(id: "claude", workingDirectory: nil, foregroundProcessGroup: 200, ttyDevice: 20)
            ], focusedTerminalID: "codex")
        let readAt = Date(timeIntervalSince1970: 100)
        func process(
            _ pid: Int32, _ group: Int32, _ tty: UInt32, _ agent: GhosttyAgentKind?,
            startedAt: Date = Date(timeIntervalSince1970: 50), alive: Bool = true,
            foreground: Int32? = nil
        ) -> GhosttyProcessSnapshot {
            .init(
                id: pid, group: group, foregroundGroup: foreground ?? group, ttyDevice: tty,
                startedAt: startedAt, executablePath: "/verified/\(pid)", agent: agent, isRunning: alive)
        }
        let node = process(100, 100, 10, nil)
        let codex = process(101, 100, 10, .codex)
        let claude = process(200, 200, 20, .claude)
        let live = [node, codex, claude].map { GhosttyProcessObservation(initial: $0, rechecked: $0) }
        let found = GhosttyAgentDetection.associations(tabs: [tab], processes: live, readAt: readAt)
        precondition(found[.init(tab: tabID, terminalID: "codex")] == .codex)
        precondition(found[.init(tab: tabID, terminalID: "claude")] == .claude)
        precondition(tab.agentKind(associations: found) == .codex)
        for invalid in [
            process(101, 999, 10, .codex), process(101, 100, 99, .codex),
            process(101, 100, 10, .codex, foreground: 999),
            process(101, 100, 10, .codex, startedAt: Date(timeIntervalSince1970: 101)),
            process(101, 100, 10, .codex, alive: false), process(101, 100, 10, nil)
        ] {
            precondition(
                GhosttyAgentDetection.associations(
                    tabs: [tab],
                    processes: [
                        .init(initial: invalid, rechecked: invalid)
                    ], readAt: readAt
                ).isEmpty)
        }
        precondition(
            GhosttyAgentDetection.associations(
                tabs: [tab],
                processes: [
                    .init(initial: codex, rechecked: nil)
                ], readAt: readAt
            ).isEmpty)
        let reused = process(101, 100, 10, .codex, startedAt: Date(timeIntervalSince1970: 51))
        precondition(
            GhosttyAgentDetection.associations(
                tabs: [tab],
                processes: [
                    .init(initial: codex, rechecked: reused)
                ], readAt: readAt
            ).isEmpty)
        let conflict = process(102, 100, 10, .claude)
        precondition(
            GhosttyAgentDetection.associations(
                tabs: [tab],
                processes: [
                    .init(initial: codex, rechecked: codex), .init(initial: conflict, rechecked: conflict)
                ], readAt: readAt
            ).isEmpty)
        let release = GhosttyTabInventory(
            application: app, tabs: [tab], readAt: readAt,
            capability: .tabsOnly, associations: found)
        precondition(release.associations.isEmpty)
    }

    static func capabilities() {
        let base = """
            <dictionary><suite>
            <class name="application" code="capp"><element type="window"/></class>
            <class name="window" code="Gwnd"><element type="tab"/><property name="id" code="ID  "/></class>
            <class name="tab" code="Gtab"><element type="terminal"/><property name="id" code="ID  "/>
            <property name="name" code="pnam"/><property name="focused terminal" code="GTfT"/></class>
            <class name="terminal" code="Gtrm"><property name="id" code="ID  "/>
            <property name="working directory" code="Gwdr"/>AGENT_PROPERTIES</class>
            <command name="select tab" code="GhstSlTb"/><command name="activate window" code="GhstAcWn"/>
            </suite></dictionary>
            """
        let release = GhosttyScriptingCapabilities.inspect(
            Data(
                base.replacingOccurrences(
                    of: "AGENT_PROPERTIES", with: ""
                ).utf8))
        precondition(release.inventory && !release.agents)
        let tip = GhosttyScriptingCapabilities.inspect(
            Data(
                base.replacingOccurrences(
                    of: "AGENT_PROPERTIES",
                    with: "<property name=\"pid\" code=\"Gpid\"/><property name=\"tty\" code=\"Gtty\"/>"
                ).utf8))
        precondition(tip.inventory && tip.agents)
        precondition(!GhosttyScriptingCapabilities.inspect(Data("<broken>".utf8)).inventory)
        precondition(
            !GhosttyScriptingCapabilities.inspect(
                Data(
                    base.replacingOccurrences(
                        of: "Gtab", with: "wrong"
                    ).utf8)
            ).inventory)
    }
}
