import Foundation

/// Reads the user's launch grants fresh each time, so editing the file needs no restart.
struct AutomationAgentProfileStore: Sendable {
    let fileURL: URL?

    static func standard() -> AutomationAgentProfileStore {
        AutomationAgentProfileStore(fileURL: nil)
    }

    nonisolated func profiles() -> [AutomationAgentProfile] {
        let fileURL =
            fileURL
            ?? AppPaths.applicationSupport()
            .appending(path: "Automation", directoryHint: .isDirectory)
            .appending(path: "agent-profiles.json", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return AutomationAgentProfile.decode(data)
    }

    nonisolated func profile(named name: String) -> AutomationAgentProfile? {
        profiles().first { $0.name == name }
    }
}
