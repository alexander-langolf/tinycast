import Foundation

/// Reads the user's launch grants fresh each time, so editing the file needs no restart.
struct AutomationAgentProfileStore: Sendable {
    let fileURL: URL

    static func standard() -> AutomationAgentProfileStore {
        AutomationAgentProfileStore(
            fileURL: AppPaths.applicationSupport()
                .appending(path: "Automation", directoryHint: .isDirectory)
                .appending(path: "agent-profiles.json", directoryHint: .notDirectory))
    }

    func profiles() -> [AutomationAgentProfile] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return AutomationAgentProfile.decode(data)
    }

    func profile(named name: String) -> AutomationAgentProfile? {
        profiles().first { $0.name == name }
    }
}
