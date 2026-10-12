#if DEBUG
    import Foundation

    extension AppCore {
        // Temporary Group 1 scratch entry point; remove before merge.
        func debugStartClaudeSession(prompt: String, directory: String) async throws -> String {
            let host = forkClaudeSessionHost
            var handle = try await host.start(prompt: prompt, directory: URL(fileURLWithPath: directory))
            for _ in 0..<20 where handle.transcriptPath == nil {
                try await Task.sleep(for: .milliseconds(100))
                guard let current = try await host.lookup(id: handle.id) else { break }
                handle = current
            }
            guard let transcriptPath = handle.transcriptPath else {
                throw ForkClaudeSessionHost.Failure.transcriptMissing(handle.id)
            }
            let chatID = UUID()
            try await forkClaudeSessionRegistry.register(
                chatID: chatID,
                entry: .init(
                    shortID: handle.id, sessionID: handle.sessionID,
                    transcriptPath: transcriptPath, folder: handle.cwd))
            return "chat=\(chatID.uuidString) id=\(handle.id) session=\(handle.sessionID)"
        }
    }
#endif
