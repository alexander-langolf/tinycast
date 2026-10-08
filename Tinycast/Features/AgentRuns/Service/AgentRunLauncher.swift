import AppKit

enum AgentRunLauncher {
    @MainActor
    static func attach(command: String, cwd: String) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--directory", (cwd as NSString).expandingTildeInPath, "/bin/zsh", "-lc", command
        ]
        _ = try await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/kitty.app"), configuration: configuration)
    }
}
