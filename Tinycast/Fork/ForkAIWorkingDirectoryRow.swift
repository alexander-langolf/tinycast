import SwiftUI

/// Where installed agents start, so Claude Code and Codex load that folder's own instructions.
struct ForkAIWorkingDirectoryRow: View {
    private var directory: ForkAIWorkingDirectory { ForkAIWorkingDirectory.current! }

    var body: some View {
        LabeledContent {
            if directory.path != nil {
                Button("Use Default") { directory.path = nil }
            }
            Button("Choose…", action: choose)
        } label: {
            SettingsRowTitle(.aiChat, ForkSettingsSearch.aiWorkingDirectoryTitle)
            Text(subtitle)
        }
        .help("Installed agents start here and read its CLAUDE.md or AGENTS.md. Tools stay off.")
    }

    private var subtitle: String {
        guard let path = directory.path else { return "Tinycast's private folder" }
        return directory.isMissing ? path + " is missing, so the private folder is used" : path
    }

    private func choose() {
        let start =
            directory.url ?? FileManager.default.homeDirectoryForCurrentUser
        guard
            let url = FolderPicker.choose(
                message: "Choose the folder installed AI agents start in.", startingAt: start)
        else { return }
        directory.path = ForkAIWorkingDirectory.setting(for: url)
    }
}
