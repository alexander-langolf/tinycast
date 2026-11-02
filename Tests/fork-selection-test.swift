import AppKit
import Synchronization

@MainActor
final class FakeForkSelectionSource: ForkSelectionSource {
    let kind: ForkSelection.Kind
    var text: String?
    private(set) var reads = 0

    init(_ kind: ForkSelection.Kind, text: String? = nil) {
        self.kind = kind
        self.text = text
    }

    func read(from app: NSRunningApplication) async -> ForkSelection? {
        reads += 1
        return text.map { ForkSelection(text: $0, source: kind) }
    }
}

@main
@MainActor
struct ForkSelectionTests {
    static func main() async throws {
        // A command-line process reports itself terminated, so the harness reads from the Dock.
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")[0]
        let accessibility = FakeForkSelectionSource(.accessibility)
        let btt = FakeForkSelectionSource(.betterTouchTool)
        let borrow = FakeForkSelectionSource(.clipboardBorrow, text: "private selection")
        let reader = ForkSelectionReader(sources: [borrow, btt, accessibility])
        let recorded = Mutex<[ForkEvent]>([])
        let selection = await ForkTrace.$recorder.withValue({ event in recorded.withLock { $0.append(event) } }) {
            await ForkTrace.run(.selectedText, category: .selection) { await reader.read(from: app) }
        }
        precondition(selection == ForkSelection(text: "private selection", source: .clipboardBorrow))
        precondition(accessibility.reads == 1 && btt.reads == 1 && borrow.reads == 1)
        let events = recorded.withLock { $0 }
        precondition(events.map(\.step) == [.start, .accessibility, .bttRead, .copySelection, .end])
        precondition(events.map(\.outcome) == [.started, .empty, .empty, .success, .success])
        precondition(Set(events.map(\.correlationID)).count == 1)
        for event in events {
            let line = try event.line()
            precondition(!String(decoding: line, as: UTF8.self).contains("private selection"))
        }

        let excluded = Mutex<[ForkEvent]>([])
        let missing = await ForkTrace.$recorder.withValue({ event in excluded.withLock { $0.append(event) } }) {
            await reader.read(from: app, allowingBorrow: false)
        }
        precondition(missing == nil && borrow.reads == 1)
        precondition(excluded.withLock { $0.map(\.step) } == [.accessibility, .bttRead])

        btt.text = "browser selection"
        let browser = await reader.read(from: app)
        precondition(browser?.source == .betterTouchTool && borrow.reads == 1)
        accessibility.text = "accessible selection"
        let accessible = await reader.read(from: app)
        precondition(accessible?.source == .accessibility && btt.reads == 3)

        accessibility.text = ""
        let empty = await reader.read(from: app)
        precondition(empty?.text == "" && empty?.source == .accessibility)
        let extensionRead = await reader.read(from: app, acceptingEmptyText: false)
        precondition(extensionRead?.source == .betterTouchTool)
        accessibility.text = "  \n"
        let whitespace = await reader.read(from: app, acceptingEmptyText: false)
        precondition(whitespace?.text == "  \n" && whitespace?.source == .accessibility)

        let beforeCancellation = accessibility.reads
        let cancelled = Task {
            await Task.yield()
            return await reader.read(from: app)
        }
        cancelled.cancel()
        let cancelledSelection = await cancelled.value
        precondition(cancelledSelection == nil && accessibility.reads == beforeCancellation)
        print("Fork selection: passed")
    }
}
