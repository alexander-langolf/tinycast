import Foundation

struct ForkClaudeSessionHooks: Sendable {
    let directory: URL

    var settingsURL: URL { directory.appending(path: "hooks.json") }
    var eventsURL: URL { directory.appending(path: "events.jsonl") }

    @concurrent
    func write() async throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = eventsURL.path.replacingOccurrences(of: "'", with: "'\"'\"'")
        let command = "/bin/cat >> '\(path)'"
        let events = [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "Notification", "Stop"
        ]
        let hooks = Dictionary(uniqueKeysWithValues: events.map { event in
            var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if ["PreToolUse", "PostToolUse", "PermissionRequest"].contains(event) {
                group["matcher"] = "*"
            }
            return (event, [group])
        })
        let data = try JSONSerialization.data(
            withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    @concurrent
    func transcriptPath(sessionID: String) async throws -> String? {
        guard FileManager.default.fileExists(atPath: eventsURL.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: eventsURL)
        defer { try? handle.close() }
        var pending = Data()
        var path: String?
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            pending.append(chunk)
            while let end = pending.firstIndex(of: 0x0A) {
                let line = pending[..<end]
                pending.removeSubrange(...end)
                guard let payload = try? JSONSerialization.jsonObject(with: Data(line))
                    as? [String: Any], payload["session_id"] as? String == sessionID,
                    let transcript = payload["transcript_path"] as? String
                else { continue }
                path = transcript
            }
        }
        return path
    }
}
