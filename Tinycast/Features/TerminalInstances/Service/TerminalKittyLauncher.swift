import AppKit

/// ⌘O: a new kitty shell in the instance's directory; never the instance's own session.
enum TerminalKittyLauncher {
    private static let application = URL(fileURLWithPath: "/Applications/kitty.app")
    private static let executable = "/Applications/kitty.app/Contents/MacOS/kitty"
    private static let bundleID = "net.kovidgoyal.kitty"

    @MainActor
    static func openShell(in directory: String) async throws {
        if let socket = runningSocket() {
            let result = await ShellCommandRunner.run(
                #"exec "$1" @ --to "$2" launch --type=tab --cwd "$3""#,
                arguments: [executable, socket, directory])
            if result.succeeded {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
                return
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--directory", directory]
        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
    }

    /// The first socket whose kitty is still alive; stale ones outlive a crash.
    nonisolated static func runningSocket() -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") else { return nil }
        for name in names.sorted() where name.hasPrefix("kitty.sock") {
            if let pid = Int32(name.dropFirst("kitty.sock-".count)), kill(pid, 0) != 0 { continue }
            return "unix:/tmp/" + name
        }
        return nil
    }
}
