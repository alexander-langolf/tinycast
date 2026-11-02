import Foundation
import Synchronization

@main
@MainActor
struct ForkObservabilityTests {
    static func main() async throws {
        let secret = "Bearer secret selected text prompt model output"
        let fields = ForkEvent.Fields(length: 42, bundleID: secret, errorCode: -1712)
        let event = ForkEvent(
            level: .info, category: .selection, operation: .quickAction,
            correlationID: UUID(), step: .accessibility, outcome: .success, fields: fields)
        let line = try event.line()
        guard let json = try JSONSerialization.jsonObject(with: line) as? [String: Any],
            let metadata = json["fields"] as? [String: String]
        else { preconditionFailure("the event must encode a JSON object with string metadata") }
        precondition(metadata["length"] == "42")
        precondition(metadata["errorCode"] == "-1712")
        precondition(metadata["bundleID"] == nil)
        precondition(!String(decoding: line, as: UTF8.self).contains(secret))
        precondition(line.last == 10 && json["time"] is String)

        precondition(metadata["caretKnown"] == nil)
        for (known, expected) in [(true, "true"), (false, "false")] {
            let caretEvent = ForkEvent(
                level: .info, category: .lyra, operation: .lyra,
                correlationID: UUID(), step: .marker, outcome: .success,
                fields: ForkEvent.Fields(caretKnown: known))
            let caretLine = try caretEvent.line()
            guard let caretJSON = try JSONSerialization.jsonObject(with: caretLine) as? [String: Any],
                  let caretMetadata = caretJSON["fields"] as? [String: String] else {
                preconditionFailure("caretKnown must encode as string metadata")
            }
            precondition(caretMetadata["caretKnown"] == expected)
        }

        let recorded = Mutex<[ForkEvent]>([])
        do {
            try await ForkTrace.$recorder.withValue({ event in recorded.withLock { $0.append(event) } }) {
                try await ForkTrace.run(.quickAction, category: .quickActions) {
                    await ForkTrace.step(.accessibility, category: .selection) {}
                    try await ForkTrace.step(.modelRequest, category: .quickActions) {
                        throw NSError(domain: secret, code: 503, userInfo: [NSLocalizedDescriptionKey: secret])
                    }
                }
            }
            preconditionFailure("the original failure must propagate")
        } catch {
            precondition((error as NSError).code == 503)
        }
        let events = recorded.withLock { $0 }
        precondition(events.count == 4)
        precondition(Set(events.map(\.correlationID)).count == 1)
        precondition(events.allSatisfy { $0.operation == .quickAction && $0.durationMS >= 0 })
        precondition(events.last?.step == .error && events.last?.outcome == .failed)
        precondition(events.last?.fields["errorCode"] == "503")
        for event in events {
            let rendered = try event.line()
            precondition(!String(decoding: rendered, as: UTF8.self).contains(secret))
        }

        let clientID = UUID()
        let clientEvents = Mutex<[ForkEvent]>([])
        await ForkTrace.$recorder.withValue({ event in clientEvents.withLock { $0.append(event) } }) {
            await ForkTrace.run(.health, category: .automation, clientID: clientID) {
                await Task {
                    do {
                        try await ForkTrace.step(.readiness, category: .supervision) {
                            throw NSError(domain: secret, code: 17)
                        }
                    } catch {}
                }.value
            }
        }
        let clientRecords = clientEvents.withLock { $0 }
        precondition(Set(clientRecords.map(\.correlationID)).count == 1)
        precondition(clientRecords.allSatisfy { $0.fields["clientID"] == clientID.uuidString })
        precondition(clientRecords.last?.outcome == .failed)
        precondition(ForkTrace.context == nil)

        let root = FileManager.default.temporaryDirectory.appending(path: "fork-logs-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mirror = ForkJSONLMirror(directory: root.appending(path: "Diagnostics"), maximumBytes: line.count + 1)
        for _ in 0..<8 { mirror.append(event) }
        await mirror.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: mirror.directory.path)
        precondition(Set(files) == Set(["events.jsonl", "events.1.jsonl", "events.2.jsonl", "events.3.jsonl"]))
        for name in files {
            let url = mirror.directory.appending(path: name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            let contents = try Data(contentsOf: url)
            precondition(contents == line)
        }
        var reader = ForkLogReader(directory: mirror.directory, filter: .init(correlationID: event.correlationID))
        let initial = try reader.read()
        precondition(initial.count == 4)
        let repeated = try reader.read()
        precondition(repeated.isEmpty)
        mirror.append(event)
        await mirror.flush()
        let followed = try reader.read()
        precondition(followed.count == 1)
        var excluded = ForkLogReader(directory: mirror.directory, filter: .init(operation: .health))
        let excludedLines = try excluded.read()
        precondition(excludedLines.isEmpty)
        var old = ForkLogReader(directory: mirror.directory, filter: .init(since: Date().addingTimeInterval(60)))
        let oldLines = try old.read()
        precondition(oldLines.isEmpty)
        var wrongLevel = ForkLogReader(directory: mirror.directory, filter: .init(level: .error))
        let wrongLevelLines = try wrongLevel.read()
        precondition(wrongLevelLines.isEmpty)

        let blocked = root.appending(path: "file")
        try Data().write(to: blocked)
        let unavailable = ForkJSONLMirror(directory: blocked.appending(path: "Diagnostics"))
        unavailable.append(event)
        await unavailable.flush()
        print("Fork observability: passed")
    }
}
