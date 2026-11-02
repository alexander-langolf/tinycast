import Foundation

@MainActor
final class FakeForkAppControl: ForkAppControl {
    var running = false
    var launches = 0
    var onTerminate: (@MainActor () -> Void)?

    func isRunning(bundleID: String) -> Bool { running }
    func launch(bundleID: String) throws { launches += 1; running = true }
    func observeTermination(bundleID: String, handler: @escaping @MainActor () -> Void) {
        onTerminate = handler
    }
    func stopObservingTermination() { onTerminate = nil }
}

@main
@MainActor
struct ForkSupervisionTests {
    static func main() async throws {
        let control = FakeForkAppControl()
        let app = ForkSupervisedApp(
            bundleID: "com.example.Companion", displayName: "Companion",
            probe: { _ in true }, policy: .init(delay: .zero))
        let supervisor = ForkAppSupervisor(app: app, control: control)
        supervisor.start()
        let ready = await supervisor.ensureReady()
        precondition(ready)
        precondition(control.launches == 1)
        for _ in 0..<3 {
            control.running = false
            control.onTerminate?()
            await supervisor.waitForPendingWork()
        }
        precondition(control.launches == 4)
        control.running = false
        control.onTerminate?()
        await supervisor.waitForPendingWork()
        precondition(supervisor.snapshot.state == .gaveUp)
        let capped = await supervisor.ensureReady()
        precondition(!capped)
        precondition(control.launches == 4)
        let repaired = await supervisor.repair()
        precondition(repaired)
        precondition(control.launches == 5 && supervisor.snapshot.relaunchCount == 0)
        supervisor.stop()
        precondition(control.onTerminate == nil)
        let stopped = await supervisor.ensureReady()
        precondition(!stopped)

        var policy = ForkRelaunchPolicy()
        let now = Date(timeIntervalSince1970: 1_000)
        for offset in 0..<3 { precondition(policy.permit(at: now.addingTimeInterval(Double(offset)))) }
        precondition(!policy.permit(at: now.addingTimeInterval(3)))
        precondition(!policy.permit(at: now.addingTimeInterval(1_000)))
        policy.reset()
        precondition(policy.permit(at: now))
        precondition(policy.permit(at: now.addingTimeInterval(601)))
        precondition(policy.count(at: now.addingTimeInterval(601)) == 1)

        precondition(ForkBTTSelectionScript.source(target: "com.example.Unsupported") == nil)
        var probes = 0
        let skipped = await ForkBTTSelectionScript.readySource(target: "com.example.Unsupported") {
            probes += 1
            return true
        }
        precondition(skipped == nil && probes == 0)
        let prepared = await ForkBTTSelectionScript.readySource(target: "com.google.Chrome") {
            probes += 1
            return true
        }
        precondition(prepared != nil && probes == 1)
        precondition(ForkBTTSelectionScript.source(target: "com.google.Chrome\"\\") == nil)
        let source = ForkBTTSelectionScript.source(target: "com.google.Chrome")!
        precondition(source.contains("tell application id \"com.hegenberg.BetterTouchTool\""))
        precondition(source.contains("with timeout of 2 seconds"))
        let marker = "trigger_action \""
        let start = source.range(of: marker)!.upperBound
        let end = source.range(of: "\"\n", range: start..<source.endIndex)!.lowerBound
        let literal = String(source[start..<end])
        var json = ""
        var escaped = false
        for character in literal {
            if escaped { json.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else { json.append(character) }
        }
        guard let action = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let target = action["BTTAdditionalActionData"] as? [String: String]
        else { preconditionFailure("the AppleScript literal must decode to the BTT action object") }
        precondition(action["BTTPredefinedActionType"] as? Int == 600)
        precondition(target["BTTActionRunJavaScriptInBrowserTarget"] == "com.google.Chrome")
        precondition((action["BTTLaunchPath"] as? String)?.contains("window.getSelection()") == true)
        print("Fork supervision: passed")
    }
}
