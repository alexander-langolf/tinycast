import AppKit

@MainActor
protocol ForkTextSink {
    func replaceSelection(in app: NSRunningApplication, with text: String) async -> Bool
}
