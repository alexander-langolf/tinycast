import AppKit
import Synchronization

enum ForkLog {
    static func record(_ event: ForkEvent) {}
}

@main
@MainActor
struct ForkLyraKittyTests {
    static func main() async {
        command()
        await selectionResults()
        placement()
        clipboardFallback()
        NSApplication.shared.setActivationPolicy(.accessory)
        copyOnly()
        print("PASSED: kitty command, selection failures, private traces, Copy-only Return and mouse placement")
    }

    static func command() {
        let bundle = URL(fileURLWithPath: "/Applications/kitty preview.app")
        let command = ForkKittySelectionSource.Command(pid: 8710, bundleURL: bundle)
        precondition(command.executable == bundle.appendingPathComponent("Contents/MacOS/kitten"))
        precondition(command.arguments == [
            "@", "--to", "unix:/tmp/kitty.sock-8710", "get-text", "--match", "state:focused", "--extent", "selection"
        ])
        let other = ForkKittySelectionSource.Command(pid: 1234, bundleURL: bundle)
        precondition(other.arguments[2] == "unix:/tmp/kitty.sock-1234")
    }

    static func selectionResults() async {
        let events = Mutex<[ForkEvent]>([])
        await ForkTrace.$recorder.withValue({ event in events.withLock { $0.append(event) } }) {
            let bundle = URL(fileURLWithPath: "/Applications/kitty.app")
            let original = "A private terminal selection\nwith another line.\n"
            let reader = ForkKittySelectionSource { _ in original }
            let selected = await reader.read(bundleID: ForkKittySelectionSource.bundleID, pid: 8710, bundleURL: bundle)
            precondition(selected?.text == original, "The reader preserves the exact selection")
            precondition(selected?.source == .kitty && reader.failure == nil)

            for text in ["", " \n\t"] {
                let empty = ForkKittySelectionSource { _ in text }
                let result = await empty.read(bundleID: ForkKittySelectionSource.bundleID, pid: 8710, bundleURL: bundle)
                precondition(result == nil && empty.failure == .empty)
                precondition(empty.failure?.message == String(localized: "Select text in kitty first"))
            }
            for failure in [ForkKittySelectionSource.Failure.unavailable, .timeout, .outputLimit] {
                let failed = ForkKittySelectionSource { _ in throw failure }
                let result = await failed.read(bundleID: ForkKittySelectionSource.bundleID, pid: 8710, bundleURL: bundle)
                precondition(result == nil && failed.failure == failure)
                precondition(failed.failure?.message == String(localized: "Lyra can't read kitty's selection"))
            }
            let cancelled = ForkKittySelectionSource { _ in throw CancellationError() }
            let cancelledRead = await cancelled.read(bundleID: ForkKittySelectionSource.bundleID, pid: 8710, bundleURL: bundle)
            precondition(cancelledRead == nil && cancelled.failure == nil, "Cancellation produces no HUD")

            var calls = 0
            let gated = ForkKittySelectionSource { _ in calls += 1; return original }
            let wrongApp = await gated.read(bundleID: "com.example.editor", pid: 8710, bundleURL: bundle)
            let missingBundle = await gated.read(bundleID: ForkKittySelectionSource.bundleID, pid: 8710, bundleURL: nil)
            precondition(wrongApp == nil && missingBundle == nil && calls == 0)
        }
        let recorded = events.withLock { $0 }
        precondition(recorded.contains { $0.outcome == .empty })
        precondition(recorded.contains { $0.outcome == .timeout })
        precondition(recorded.contains { $0.outcome == .failed && $0.fields["errorCode"] != nil })
        precondition(recorded.contains { $0.outcome == .success && $0.fields["length"] != nil })
        for event in recorded {
            precondition(Set(event.fields.keys).isSubset(of: ["length", "bundleID", "errorCode"]))
            let line = String(decoding: try! event.line(), as: UTF8.self)
            precondition(!line.contains("private terminal") && !line.contains("kitty.sock"))
        }
    }

    /// A TUI that captures the mouse leaves kitty without a selection; its own copy is the fallback.
    static func clipboardFallback() {
        let now = Date()
        let kitty = ForkKittySelectionSource.bundleID
        func fallback(_ text: String?, _ source: String?, _ age: TimeInterval) -> String? {
            ForkKittySelectionSource.clipboardFallback(
                text: text, sourceBundleID: source, createdAt: now.addingTimeInterval(-age), now: now)
        }
        precondition(fallback("copied in Claude Code", kitty, 5) == "copied in Claude Code")
        precondition(fallback("copied in Claude Code", kitty, 120) == "copied in Claude Code")
        precondition(fallback("stale", kitty, 121) == nil, "An old copy is not the current selection")
        precondition(fallback("from Slack", "com.tinyspeck.slackmacgap", 5) == nil, "Only kitty's own copies count")
        precondition(fallback(nil, kitty, 5) == nil)
        precondition(fallback("  \n", kitty, 5) == nil)
        precondition(fallback("unknown source", nil, 5) == nil)
    }

    static func placement() {
        let size = CGSize(width: 400, height: 160)
        for visible in [CGRect(x: 0, y: 0, width: 1440, height: 875),
                        CGRect(x: -1600, y: -400, width: 1500, height: 900)] {
            for mouse in [CGPoint(x: visible.midX, y: visible.midY),
                          CGPoint(x: visible.minX, y: visible.minY),
                          CGPoint(x: visible.maxX - 1, y: visible.maxY - 1)] {
                let origin = ForkLyraSuggestionController.mousePanelOrigin(mouse, panelSize: size, visible: visible)
                precondition(visible.contains(CGRect(origin: origin, size: size)))
                precondition(abs(origin.x - mouse.x) <= size.width + 12)
                precondition(abs(origin.y - mouse.y) <= size.height + 12)
            }
            let middle = CGPoint(x: visible.midX, y: visible.midY)
            let origin = ForkLyraSuggestionController.mousePanelOrigin(middle, panelSize: size, visible: visible)
            precondition(origin == CGPoint(x: middle.x + 12, y: middle.y - size.height - 12),
                         "A normal mouse anchor stays near the pointer instead of the screen top")
        }
    }

    static func copyOnly() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let controller = ForkLyraSuggestionController(pasteboard: pasteboard)
        defer { controller.dismiss() }
        var applies = 0
        var dismissals = 0
        controller.onDismiss = { dismissals += 1 }
        let mouse = NSEvent.mouseLocation
        controller.showRewrite(near: mouse, original: "Selected terminal text")
        precondition(controller.copyOnly)
        controller.acceptRewrite { applies += 1 }
        precondition(applies == 0 && dismissals == 0 && pasteboard.string(forType: .string) == nil)
        controller.updateRewrite("Partial")
        controller.acceptRewrite { applies += 1 }
        precondition(applies == 0 && dismissals == 0)
        controller.updateRewrite("Failed", isError: true)
        controller.acceptRewrite { applies += 1 }
        precondition(applies == 0 && dismissals == 0)
        controller.updateRewrite("Completed rewrite", isComplete: true)
        let panel = NSApp.windows.first { $0.isVisible && $0 is NSPanel }
        precondition(panel != nil)
        if let panel {
            let visible = NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame ?? NSScreen.main!.visibleFrame
            precondition(panel.frame.origin == ForkLyraSuggestionController.mousePanelOrigin(
                mouse, panelSize: panel.frame.size, visible: visible))
            let button = descendants(panel.contentView!).compactMap { $0 as? NSButton }.first!
            button.performClick(nil)
            precondition(pasteboard.string(forType: .string) == "Completed rewrite")
            precondition(controller.kind == .rewrite && applies == 0 && dismissals == 0)
        }
        pasteboard.clearContents()
        controller.acceptRewrite { applies += 1 }
        precondition(pasteboard.string(forType: .string) == "Completed rewrite")
        precondition(controller.kind == .hidden && applies == 0 && dismissals == 1,
                     "Return copies and dismisses without calling the apply closure")
        controller.showRewrite(at: .zero, caretKnown: false, original: "Editable field")
        precondition(!controller.copyOnly, "An ordinary rewrite resets Copy-only delivery")
        controller.updateRewrite("Editable rewrite", isComplete: true)
        controller.acceptRewrite { applies += 1 }
        precondition(applies == 1 && dismissals == 1)
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
