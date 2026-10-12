import Foundation

struct GhosttyProcessSnapshot: Hashable, Sendable {
    let id: Int32
    let group: Int32
    let foregroundGroup: Int32
    let ttyDevice: UInt32
    let startedAt: Date
    let executablePath: String
    let agent: GhosttyAgentKind?
    let isRunning: Bool
}

struct GhosttyProcessObservation: Sendable {
    let initial: GhosttyProcessSnapshot
    let rechecked: GhosttyProcessSnapshot?
}

enum GhosttyAgentDetection {
    static func associations(
        tabs: [GhosttyTabSnapshot], processes: [GhosttyProcessObservation],
        readAt: Date
    ) -> [GhosttyTerminalIdentity: GhosttyAgentKind] {
        var result: [GhosttyTerminalIdentity: GhosttyAgentKind] = [:]
        for tab in tabs {
            for terminal in tab.terminals {
                guard let group = terminal.foregroundProcessGroup, group > 0,
                    let tty = terminal.ttyDevice
                else { continue }
                let kinds = Set(
                    processes.compactMap { observation -> GhosttyAgentKind? in
                        let process = observation.initial
                        guard process == observation.rechecked, process.isRunning,
                            process.startedAt <= readAt, process.group == group,
                            process.foregroundGroup == group, process.ttyDevice == tty
                        else { return nil }
                        return process.agent
                    })
                if kinds.count == 1 {
                    result[.init(tab: tab.id, terminalID: terminal.id)] = kinds.first
                }
            }
        }
        return result
    }
}
