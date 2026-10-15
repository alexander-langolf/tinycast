struct NotchPolicy: Sendable {
    enum Target: Sendable { case expanded, retracted, stopped }

    private(set) var target: Target = .expanded
    private(set) var identity: UInt64 = 0

    mutating func expand() -> Bool { move(to: .expanded) }
    mutating func retract() -> Bool { move(to: .retracted) }

    mutating func stop() { _ = move(to: .stopped) }

    func accepts(_ identity: UInt64) -> Bool { self.identity == identity && target != .stopped }

    private mutating func move(to next: Target) -> Bool {
        guard target != .stopped, target != next else { return false }
        target = next
        identity &+= 1
        return true
    }
}
