import Foundation

struct PersistentLauncherPolicy: Sendable {
    enum Phase: Sendable { case resting, opening, active, closing, stopped }

    private(set) var phase: Phase = .resting
    private(set) var identity: UInt64 = 0
    private(set) var sessionIdentity: UInt64 = 0
    var isActive: Bool { phase == .opening || phase == .active }

    mutating func summon() -> Bool {
        guard phase != .stopped, !isActive else { return false }
        identity &+= 1
        sessionIdentity &+= 1
        phase = .opening
        return true
    }

    mutating func dismiss() -> Bool {
        guard isActive else { return false }
        identity &+= 1
        phase = .closing
        return true
    }

    mutating func retarget() {
        guard phase == .opening || phase == .closing else { return }
        identity &+= 1
    }

    mutating func complete(_ identity: UInt64) {
        guard self.identity == identity else { return }
        if phase == .opening { phase = .active }
        if phase == .closing { phase = .resting }
    }

    mutating func quit() -> Bool {
        let teardown = isActive
        identity &+= 1
        phase = .stopped
        return teardown
    }
}
