import Foundation

@MainActor
protocol ForkProcessControl: AnyObject {
    func healthy() async -> Bool
    func portIsFree() -> Bool
    func recordedPID() async -> Int32?
    func isRunning(_ pid: Int32) -> Bool
    func launch(modelPath: String) throws -> Int32
    func stop(_ pid: Int32) async
}
