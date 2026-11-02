import Foundation
import Synchronization

@main
@MainActor
struct ForkPolicyTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = directory.appending(path: "policy")
        try FileManager.default.copyItem(at: URL(filePath: "server"), to: policy)
        let original = try ForkPolicySnapshot.load(directory: policy)
        precondition(original.version.count == 12)
        precondition(original.version.allSatisfy { $0.isHexDigit })
        precondition(original.policy.fix.delay(for: "one two") == nil)
        precondition(original.policy.fix.delay(for: "one two three") == .milliseconds(500))
        precondition(original.policy.selection.accepts("one two three"))
        precondition(!original.policy.selection.accepts("one two"))
        precondition(!original.policy.selection.accepts("one two " + String(repeating: "x", count: 993)))
        let file = policy.appending(path: "policy/lyra.json")
        let bytes = try Data(contentsOf: file)
        let text = String(decoding: bytes, as: UTF8.self)
        let invalid = [
            "{", text.replacingOccurrences(of: "\"selection\": {", with: "\"selection\": {\"unknown\": 1,"),
            text.replacingOccurrences(of: "\"name\": \"fix\"", with: "\"unknown\": 1, \"name\": \"fix\""),
            text.replacingOccurrences(of: "\"pauseMs\": 500", with: "\"pauseMs\": 60001"),
            text.replacingOccurrences(of: "\"maxCharacters\": 1000", with: "\"maxCharacters\": 100001"),
            text.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2"),
            text.replacingOccurrences(of: "\"minWords\": 3", with: "\"minWords\": -1"),
            text.replacingOccurrences(of: "\"minWords\": 3", with: "\"minWords\": 3.5"),
            text.replacingOccurrences(of: "\"pauseMs\": 500", with: "\"pauseMs\": true"),
            text.replacingOccurrences(of: "\"fix\": {", with: "\"fix\": {\"unknown\": 1,"),
            text.replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"unknown\": 1, \"schemaVersion\": 1"),
            text.replacingOccurrences(of: "prompts/fix.txt", with: "../private.txt"),
            text.replacingOccurrences(of: "\"fix\": \"local\"", with: "\"fix\": \"connection name\"")
        ]
        for invalidText in invalid {
            try Data(invalidText.utf8).write(to: file, options: .atomic)
            do { _ = try ForkPolicySnapshot.load(directory: policy); preconditionFailure("invalid policy accepted") }
            catch is ForkPolicyFailure { }
        }
        try bytes.write(to: file, options: .atomic)
        let prompt = policy.appending(path: "prompts/fix.txt")
        let oldPrompt = try Data(contentsOf: prompt)
        try Data((String(decoding: oldPrompt, as: UTF8.self) + "\n").utf8).write(to: prompt, options: .atomic)
        let promptChange = try ForkPolicySnapshot.load(directory: policy)
        precondition(promptChange.version != original.version)
        try oldPrompt.write(to: prompt, options: .atomic)
        let restored = try ForkPolicySnapshot.load(directory: policy)
        precondition(restored.version == original.version)

        try Data().write(to: prompt, options: .atomic)
        do { _ = try ForkPolicySnapshot.load(directory: policy); preconditionFailure("empty prompt accepted") }
        catch let failure as ForkPolicyFailure { precondition(failure.reason == .invalidPrompt) }
        try FileManager.default.removeItem(at: prompt)
        do { _ = try ForkPolicySnapshot.load(directory: policy); preconditionFailure("missing prompt accepted") }
        catch let failure as ForkPolicyFailure { precondition(failure.reason == .unreadable) }
        try oldPrompt.write(to: prompt, options: .atomic)
        let connectionID = UUID()
        try Data(text.replacingOccurrences(of: "\"fix\": \"local\"", with: "\"fix\": \"\(connectionID.uuidString)\"").utf8)
            .write(to: file, options: .atomic)
        let routed = try ForkPolicySnapshot.load(directory: policy)
        precondition(routed.policy.routing[.fix] == .connection(connectionID))
        let customText = text.replacingOccurrences(of: "friendly", with: "concise")
        try Data(customText.utf8).write(to: file, options: .atomic)
        let concise = ForkLyraMode(rawValue: "concise")!
        try oldPrompt.write(to: policy.appending(path: "prompts/concise.txt"), options: .atomic)
        let custom = try ForkPolicySnapshot.load(directory: policy)
        precondition(custom.policy.availableModes.contains(concise))
        precondition(!custom.policy.availableModes.contains(.friendly))
        let customRewrite = try ForkLyraArguments(arguments: ["mode": .string("concise")], modes: custom.policy.availableModes)
        precondition(customRewrite.mode == concise)
        try bytes.write(to: file, options: .atomic)

        let suite = "fork-policy-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ForkPolicyStore(defaults: defaults, fallbackDirectory: URL(filePath: "server"))
        store.directory = policy.path
        await store.reload()
        precondition(store.snapshot?.version == original.version)
        try Data("{ selected text must never reach logs".utf8).write(to: file, options: .atomic)
        let events = Mutex<[ForkEvent]>([])
        await ForkTrace.$recorder.withValue({ event in events.withLock { $0.append(event) } }) {
            await store.reload()
        }
        precondition(store.snapshot?.version == original.version)
        let rejection = events.withLock { $0.last }
        precondition(rejection?.outcome == .failed)
        precondition(rejection?.fields["policyFile"] == "lyra.json")
        precondition(rejection?.fields["policyFailure"] == "invalidJSON")
        precondition(rejection?.fields["policyVersion"] == original.version)
        let rejectedLine = try rejection!.line()
        precondition(!String(decoding: rejectedLine, as: UTF8.self).contains("selected text"))
        try Data(text.replacingOccurrences(of: "\"minWords\": 3", with: "\"minWords\": 5").utf8)
            .write(to: file, options: .atomic)
        await store.reload()
        precondition(store.snapshot?.version != original.version)
        precondition(store.snapshot?.policy.fix.delay(for: "one two three four") == nil)
        store.directory = directory.appending(path: "missing").path
        await store.reload()
        precondition(store.snapshot?.version == original.version)
        store.stop()

        let watchedDirectory = directory.appending(path: "watched")
        try FileManager.default.copyItem(at: URL(filePath: "server"), to: watchedDirectory)
        store.directory = watchedDirectory.path
        store.start()
        try await wait { store.snapshot?.version == original.version }
        let watchedFile = watchedDirectory.appending(path: "policy/lyra.json")
        try Data(text.replacingOccurrences(of: "\"minWords\": 3", with: "\"minWords\": 5").utf8)
            .write(to: watchedFile, options: .atomic)
        try await wait { store.snapshot?.policy.fix.delay(for: "one two three four") == nil }
        let watchedVersion = store.snapshot!.version
        let watchedPrompt = watchedDirectory.appending(path: "prompts/fix.txt")
        try Data((String(decoding: oldPrompt, as: UTF8.self) + "\n").utf8).write(to: watchedPrompt, options: .atomic)
        try await wait { store.snapshot?.version != watchedVersion }
        store.stop()

        let fields = ForkEvent.Fields(policyVersion: "selected text", policyFile: "../private.txt")
        precondition(fields.values["policyVersion"] == nil && fields.values["policyFile"] == nil)
        let validFields = ForkEvent.Fields(policyVersion: original.version)
        precondition(validFields.values["policyVersion"] == original.version)
        let traced = Mutex<[ForkEvent]>([])
        await ForkTrace.$recorder.withValue({ event in traced.withLock { $0.append(event) } }) {
            await ForkTrace.run(.lyra, category: .lyra, fields: validFields) {
                ForkTrace.begin(.lyra, category: .lyra, step: .trigger).end()
            }
        }
        precondition(traced.withLock { $0.allSatisfy { $0.fields["policyVersion"] == original.version } })
        print("PASSED: strict runtime policy, versioning, fallback and private diagnostics")
    }

    private static func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
        precondition(predicate(), "policy watcher did not publish the expected snapshot")
    }
}
