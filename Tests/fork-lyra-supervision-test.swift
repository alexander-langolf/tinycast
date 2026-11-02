import Foundation

@MainActor
final class FakeLyraProcessControl: ForkProcessControl {
    var ready = true
    var free = true
    var recorded: Int32?
    var running: Set<Int32> = []
    var launches = 0
    var stopped: [Int32] = []
    var becomeReadyOnLaunch = true

    func healthy() async -> Bool { ready }
    func portIsFree() -> Bool { free }
    func recordedPID() async -> Int32? { recorded }
    func isRunning(_ pid: Int32) -> Bool { running.contains(pid) }
    func launch(modelPath: String) throws -> Int32 {
        launches += 1
        ready = becomeReadyOnLaunch
        running.insert(42)
        return 42
    }
    func stop(_ pid: Int32) async { stopped.append(pid); running.remove(pid) }
}

@main
@MainActor
struct ForkLyraSupervisionTests {
    static func main() async throws {
        let reused = FakeLyraProcessControl()
        let external = ForkProcessSupervisor(name: "llama-server", control: reused)
        try await external.start(modelPath: "model")
        precondition(external.snapshot.ownership == .reused && reused.launches == 0)
        reused.ready = false
        await external.refreshHealth()
        precondition(external.snapshot.state == .notRunning)
        await external.stop()
        precondition(reused.stopped.isEmpty)

        let recorded = FakeLyraProcessControl()
        recorded.recorded = 7
        recorded.running.insert(7)
        let adopted = ForkProcessSupervisor(name: "llama-server", control: recorded)
        try await adopted.start(modelPath: "model")
        precondition(adopted.snapshot.ownership == .adopted && adopted.snapshot.pid == 7)
        await adopted.stop()
        precondition(recorded.stopped == [7] && recorded.launches == 0)

        let owned = FakeLyraProcessControl()
        owned.ready = false
        let started = ForkProcessSupervisor(name: "llama-server", control: owned)
        try await started.start(modelPath: "model")
        precondition(started.snapshot.state == .running && started.snapshot.ownership == .started)
        precondition(owned.launches == 1)
        await started.stop()
        await started.stop()
        precondition(owned.stopped == [42])

        let occupied = FakeLyraProcessControl()
        occupied.ready = false
        occupied.free = false
        let refused = ForkProcessSupervisor(name: "llama-server", control: occupied)
        do { try await refused.start(modelPath: "model"); preconditionFailure("occupied port accepted") }
        catch ForkProcessSupervisor.Failure.occupied { }
        precondition(occupied.launches == 0 && occupied.stopped.isEmpty)

        let loading = FakeLyraProcessControl()
        loading.ready = false
        loading.becomeReadyOnLaunch = false
        let timedOut = ForkProcessSupervisor(name: "llama-server", control: loading)
        do { try await timedOut.start(modelPath: "model", timeout: .zero); preconditionFailure("startup timeout accepted") }
        catch ForkProcessSupervisor.Failure.timeout { }
        precondition(loading.stopped == [42] && timedOut.snapshot.state == .failed)
        print("PASSED: Lyra server reuse, adoption, owned shutdown and refusal")
    }
}
