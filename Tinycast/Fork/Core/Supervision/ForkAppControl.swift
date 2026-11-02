import Foundation

@MainActor
protocol ForkAppControl: AnyObject {
    func isRunning(bundleID: String) -> Bool
    func launch(bundleID: String) throws
    func observeTermination(bundleID: String, handler: @escaping @MainActor () -> Void)
    func stopObservingTermination()
}

struct ForkSupervisedApp: Sendable {
    let bundleID: String
    let displayName: String
    let probe: @MainActor @Sendable (TimeInterval) async -> Bool
    var policy = ForkRelaunchPolicy()
}

struct ForkRelaunchPolicy: Sendable {
    var delay: Duration = .seconds(2)
    var limit = 3
    var window: TimeInterval = 600
    private var launches: [Date] = []
    private(set) var gaveUp = false

    init(delay: Duration = .seconds(2), limit: Int = 3, window: TimeInterval = 600) {
        self.delay = delay
        self.limit = limit
        self.window = window
    }

    func count(at date: Date) -> Int { launches.filter { date.timeIntervalSince($0) < window }.count }

    mutating func permit(at date: Date) -> Bool {
        guard !gaveUp else { return false }
        launches.removeAll { date.timeIntervalSince($0) >= window }
        guard launches.count < limit else { gaveUp = true; return false }
        launches.append(date)
        return true
    }

    mutating func reset() { launches = []; gaveUp = false }
}
