import AppKit

@MainActor
protocol ForkSelectionSource {
    var kind: ForkSelection.Kind { get }
    func read(from app: NSRunningApplication) async -> ForkSelection?
}
