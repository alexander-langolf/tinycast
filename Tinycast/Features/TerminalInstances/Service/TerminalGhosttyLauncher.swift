import AppKit

enum TerminalGhosttyLauncher {
    private static let application = URL(filePath: "/Applications/Ghostty.app")
    private static let bundleID = "com.mitchellh.ghostty"

    @MainActor
    static func openShell(in directory: String) async throws {
        try Task.checkCancellation()
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        if let running = applications.first(where: { $0.isActive })
            ?? applications.first(where: { $0.bundleURL == application }) ?? applications.first
        {
            guard let target = running.bundleURL else {
                throw ScriptFailure("The running Ghostty application's location is unavailable.")
            }
            try await runScript(source(application: target, directory: directory))
            try Task.checkCancellation()
            guard !running.isTerminated, running.bundleURL == target else { return }
            running.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.promptsUserIfNeeded = false
        configuration.arguments = ["--working-directory=\(directory)"]
        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        try Task.checkCancellation()
    }

    private static func source(application: URL, directory: String) -> String {
        """
        using terms from application "/Applications/Ghostty.app"
            set targetApplication to \(stringLiteral(application.path))
            tell application targetApplication
                set surfaceConfig to new surface configuration from {initial working directory:\(stringLiteral(directory))}
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

    private static func stringLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    private nonisolated static func runScript(_ source: String) async throws {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let script = NSAppleScript(source: source) else {
                throw ScriptFailure("The Ghostty automation could not be prepared.")
            }
            try Task.checkCancellation()
            var errorInfo: NSDictionary?
            _ = script.executeAndReturnError(&errorInfo)
            try Task.checkCancellation()
            guard let errorInfo else { return }
            if errorInfo[NSAppleScript.errorNumber] as? Int == -1743 {
                throw ScriptFailure(
                    "Allow Tinycast to control Ghostty in System Settings → Privacy & Security → Automation.")
            }
            throw ScriptFailure(
                errorInfo[NSAppleScript.errorMessage] as? String ?? "The Ghostty automation failed.")
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private struct ScriptFailure: LocalizedError, Sendable {
        let errorDescription: String?

        init(_ description: String) { errorDescription = description }
    }
}
