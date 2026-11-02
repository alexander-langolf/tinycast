import AppKit

// FORK: btt-selection
enum ForkBTTBrowserSelection {
    @MainActor
    static func read(from app: NSRunningApplication) async -> String? {
        let span = ForkTrace.begin(.bttSelection, category: .betterTouchTool, step: .bttRead)
        guard let bundleID = app.bundleIdentifier, ForkBTTSelectionScript.browsers.contains(bundleID)
        else { span.end(.skipped); return nil }
        let source = await ForkBTTSelectionScript.readySource(target: bundleID) {
            guard let supervisor = ForkSupervision.current?.betterTouchTool else { return false }
            return await supervisor.ensureReady()
        }
        guard let source, !Task.isCancelled, !app.isTerminated
        else { span.end(Task.isCancelled ? .cancelled : .unavailable); return nil }
        let reply = await execute(source)
        guard !Task.isCancelled, !app.isTerminated else { span.end(.cancelled); return nil }
        let text = reply.text.flatMap { text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.hasPrefix("{\"error\"")
                ? nil : text
        }
        span.end(
            reply.errorCode == -1712 ? .timeout : reply.errorCode != nil ? .failed : text == nil ? .empty : .success,
            fields: .init(length: text?.count, bundleID: bundleID, errorCode: reply.errorCode))
        return text
    }

    private struct Reply: Sendable {
        let text: String?
        let errorCode: Int?
    }

    @concurrent
    private static func execute(_ source: String) async -> Reply {
        guard !Task.isCancelled, let apple = NSAppleScript(source: source) else {
            return Reply(text: nil, errorCode: -1)
        }
        var error: NSDictionary?
        let result = apple.executeAndReturnError(&error)
        return Reply(text: error == nil ? result.stringValue : nil,
                     errorCode: error == nil ? nil : (error?[NSAppleScript.errorNumber] as? Int ?? -1))
    }
}
