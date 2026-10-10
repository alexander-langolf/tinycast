import Foundation

extension AppCore {
    var forkClaudeSessionDirectory: URL {
        AppPaths.applicationSupport().appending(path: "ClaudeSessions", directoryHint: .isDirectory)
    }

    func makeForkClaudeSessionHost() -> ForkClaudeSessionHost {
        ForkClaudeSessionHost(directory: forkClaudeSessionDirectory) { [weak self] in
            self?.aiSettings.override(for: .claude).commandPath ?? ""
        }
    }
}
