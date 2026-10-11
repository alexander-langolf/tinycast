import AppKit
import Synchronization

enum TerminalGhosttyLauncher {
    private static let application = URL(filePath: "/Applications/Ghostty.app")
    private static let bundleID = "com.mitchellh.ghostty"

    @MainActor
    static func openShell(in directory: String, command: String? = nil) async throws {  // FORK: file-navigator
        try Task.checkCancellation()
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        if let running = applications.first(where: { $0.isActive })
            ?? applications.first(where: { $0.bundleURL == application }) ?? applications.first
        {
            guard let target = running.bundleURL else {
                throw ScriptFailure("The running Ghostty application's location is unavailable.")
            }
            try await runScript(source(application: target, directory: directory, command: command))
            try Task.checkCancellation()
            guard !running.isTerminated, running.bundleURL == target else { return }
            running.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        // FORK: file-navigator
        var arguments = ["--working-directory=\(directory)"]
        if let command {
            arguments += ["--wait-after-command=true", "-e", "/bin/zsh", "-ilc", command]
        }
        configuration.arguments = arguments
        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        try Task.checkCancellation()
    }

    private static func source(application: URL, directory: String, command: String?) -> String {
        // FORK: file-navigator
        let editor =
            command.map {
                ", command:" + stringLiteral("/bin/zsh -ilc " + shellQuote($0)) + ", wait after command:true"
            } ?? ""
        return """
            using terms from application \(stringLiteral(application.path))
                set targetApplication to \(stringLiteral(application.path))
                tell application targetApplication
                    set surfaceConfig to new surface configuration from {initial working directory:\(stringLiteral(directory))\(editor)}
                    if (count of windows) is 0 then
                        set targetWindow to new window with configuration surfaceConfig
                    else
                        set targetWindow to front window
                        set targetTab to new tab in targetWindow with configuration surfaceConfig
                        select tab targetTab
                    end if
                    activate window targetWindow
                end tell
            end using terms from
            """
    }

    // FORK: file-navigator
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func stringLiteral(_ value: String) -> String {
        "\""
            + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    /// One script at a time: NSAppleScript is not safe to run concurrently from background threads.
    private static let scriptQueue = DispatchQueue(
        label: "com.tinycast.ghostty-launcher", qos: .userInitiated)

    private nonisolated static func runScript(_ source: String) async throws {
        try Task.checkCancellation()
        // FORK: file-navigator
        let cancelled = Mutex(false)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                scriptQueue.async {
                    guard !cancelled.withLock({ $0 }) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let script = NSAppleScript(source: source) else {
                        continuation.resume(
                            throwing: ScriptFailure("The Ghostty automation could not be prepared."))
                        return
                    }
                    var errorInfo: NSDictionary?
                    _ = script.executeAndReturnError(&errorInfo)
                    guard let errorInfo else {
                        continuation.resume()
                        return
                    }
                    if errorInfo[NSAppleScript.errorNumber] as? Int == -1743 {
                        continuation.resume(
                            throwing: ScriptFailure(
                                "Allow Tinycast to control Ghostty in System Settings → Privacy & Security → Automation."
                            ))
                        return
                    }
                    continuation.resume(
                        throwing: ScriptFailure(
                            errorInfo[NSAppleScript.errorMessage] as? String
                                ?? "The Ghostty automation failed."))
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
        try Task.checkCancellation()
    }

    private struct ScriptFailure: LocalizedError, Sendable {
        let errorDescription: String?

        init(_ description: String) { errorDescription = description }
    }
}
