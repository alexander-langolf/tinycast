import AppKit
import Carbon
import Synchronization

@main @MainActor
struct GhosttyStatusLifecycleTests {
    static func main() async {
        do { try allElementsSpecifier() } catch {
            preconditionFailure("Apple Event descriptor construction failed: \(error)")
        }
        await lifecycle()
        await cancelledQueue()
        print("Ghostty status lifecycle, coalescing and queued cancellation passed")
    }

    static func allElementsSpecifier() throws {
        let target = GhosttyApplicationTarget(
            identity: .init(processID: 42, launchedAt: .distantPast),
            bundleURL: URL(filePath: "/test/Ghostty.app"))
        let session = GhosttyEventSession(target: target, cancelled: GhosttyRequestCancellation())
        let window = try session.allSpecifier("Gwnd", of: .null())
        precondition(window.descriptorType == typeObjectSpecifier)
        precondition(field(AEKeyword(keyAEDesiredClass), in: window).typeCodeValue == 0x47776e64)
        precondition(field(AEKeyword(keyAEKeyForm), in: window).enumCodeValue == OSType(formAbsolutePosition))
        let ordinal = field(AEKeyword(keyAEKeyData), in: window)
        precondition(ordinal.descriptorType == typeAbsoluteOrdinal)
        precondition(ordinal.data == NSAppleEventDescriptor(enumCode: OSType(kAEAll)).data)
        precondition(field(AEKeyword(keyAEContainer), in: window).descriptorType == typeNull)
        let tab = try session.allSpecifier("Gtab", of: window)
        precondition(field(AEKeyword(keyAEContainer), in: tab).data == window.data)
    }

    static func field(_ key: AEKeyword, in object: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        var result = AEDesc()
        precondition(AEGetParamDesc(object.aeDesc, key, typeWildCard, &result) == noErr)
        return NSAppleEventDescriptor(aeDescNoCopy: &result)
    }

    static func lifecycle() async {
        let reader = Reader()
        let coordinator = GhosttyStatusCoordinator(dependencies: reader.dependencies)
        coordinator.start(observeLifecycle: false)
        await until { reader.readCount == 1 }
        for _ in 0..<5 { coordinator.requestRefresh() }
        coordinator.applicationDidChange(terminated: false)
        precondition(reader.readCount == 1 && reader.activeReads == 1)
        reader.complete(.loaded(reader.inventory(["stale"])))
        await until { reader.readCount == 2 }
        precondition(coordinator.tabs.isEmpty, "an invalidated response cannot restore cards")
        reader.complete(.loaded(reader.inventory(["one", "two", "three"])))
        await until { !coordinator.isReading }
        precondition(coordinator.tabs.map(\.id.tabID) == ["one", "two", "three"])
        coordinator.requestRefresh()
        await until { reader.readCount == 3 }
        reader.complete(.loaded(reader.inventory(["one", "three"])))
        await until { !coordinator.isReading }
        precondition(
            coordinator.tabs.dropFirst().map(\.id.tabID) == ["three"], "overflow derives from current tabs")
        coordinator.setResting(false)
        coordinator.setSuspended(true)
        coordinator.setSuspended(false)
        coordinator.requestRefresh()
        await Task.yield()
        precondition(
            reader.readCount == 3 && !coordinator.canRefresh, "wake must preserve active palette intent")
        coordinator.setResting(true)
        await until { reader.readCount == 4 }
        let old = reader.inventory(["old launch"])
        reader.target = .init(
            identity: .init(processID: 42, launchedAt: Date(timeIntervalSince1970: 2)),
            bundleURL: reader.target.bundleURL)
        coordinator.applicationDidChange(terminated: true)
        reader.complete(.loaded(old))
        await until { reader.readCount == 5 }
        precondition(coordinator.tabs.isEmpty)
        coordinator.setSuspended(true)
        reader.complete(.loaded(reader.inventory(["sleep stale"])))
        await until { !coordinator.isReading }
        precondition(coordinator.tabs.isEmpty)
        coordinator.setSuspended(false)
        await until { reader.readCount == 6 }
        coordinator.stop()
        reader.complete(.loaded(reader.inventory(["stop stale"])))
        await until { !coordinator.isReading }
        precondition(coordinator.tabs.isEmpty && reader.maxReads == 1)
    }

    static func cancelledQueue() async {
        let queue = DispatchQueue(label: "ghostty-test-queue")
        let gate = DispatchSemaphore(value: 0)
        let executed = Mutex(false)
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(); gate.wait()
            }
        }
        var started = false
        let request = Task {
            started = true
            return await GhosttySerializedRequest.run(on: queue, fallback: false) { cancellation in
                guard !cancellation.isCancelled else { return false }
                executed.withLock { $0 = true }
                return true
            }
        }
        await until { started }
        request.cancel()
        gate.signal()
        let result = await request.value
        precondition(!result && !executed.withLock { $0 }, "a cancelled queued selection must not execute")
    }

    static func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("condition did not settle")
    }
}

@MainActor
private final class Reader {
    var target = GhosttyApplicationTarget(
        identity: .init(processID: 42, launchedAt: Date(timeIntervalSince1970: 1)),
        bundleURL: URL(filePath: "/test/Ghostty.app"))
    var readCount = 0
    var activeReads = 0
    var maxReads = 0
    var continuation: CheckedContinuation<GhosttyStatusState, Never>?

    var dependencies: GhosttyStatusDependencies {
        .init(
            currentTarget: { self.target },
            read: { _ in
                self.readCount += 1
                self.activeReads += 1
                self.maxReads = max(self.maxReads, self.activeReads)
                let result = await withCheckedContinuation { self.continuation = $0 }
                self.activeReads -= 1
                return result
            })
    }

    func complete(_ state: GhosttyStatusState) {
        guard let continuation else { preconditionFailure("no pending read") }
        self.continuation = nil
        continuation.resume(returning: state)
    }

    func inventory(_ names: [String]) -> GhosttyTabInventory {
        .init(
            application: target.identity,
            tabs: names.map {
                .init(
                    id: .init(application: target.identity, windowID: "window", tabID: $0),
                    title: $0, terminals: [], focusedTerminalID: nil)
            }, readAt: Date())
    }
}
