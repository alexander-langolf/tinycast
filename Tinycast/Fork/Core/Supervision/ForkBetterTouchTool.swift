import Foundation

enum ForkBetterTouchTool {
    static let bundleID = "com.hegenberg.BetterTouchTool"
    static let probeSource = """
        with timeout of 1 second
          tell application id "com.hegenberg.BetterTouchTool" to get_string_variable "tinycast_probe"
        end timeout
        """

    @MainActor
    static var descriptor: ForkSupervisedApp {
        ForkSupervisedApp(bundleID: bundleID, displayName: "BetterTouchTool", probe: { timeout in
            guard timeout >= 1 else { return false }
            return await probe()
        })
    }

    @concurrent
    private static func probe() async -> Bool {
        let span = ForkTrace.begin(.appSupervision, category: .betterTouchTool, step: .readiness)
        guard !Task.isCancelled, let script = NSAppleScript(source: probeSource) else {
            span.end(Task.isCancelled ? .cancelled : .failed)
            return false
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        let code = error == nil ? nil : (error?[NSAppleScript.errorNumber] as? Int ?? -1)
        span.end(Task.isCancelled ? .cancelled : code == -1712 ? .timeout : error == nil ? .success : .failed,
                 fields: .init(bundleID: bundleID, errorCode: code))
        return error == nil && !Task.isCancelled
    }
}
