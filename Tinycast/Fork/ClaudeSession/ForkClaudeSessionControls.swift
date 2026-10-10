import SwiftUI

enum ForkClaudeSessionControls {
    struct ApprovalBadge: View {
        let sessions: ForkClaudeSessionCoordinator
        let chatID: UUID

        var body: some View {
            if sessions.approvalTool(chatID: chatID) != nil {
                SymbolImage(name: "exclamationmark.circle.fill", size: Theme.Size.aiChatComposerGlyph)
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityLabel("Claude needs approval")
            }
        }
    }

    struct SessionLabel: View {
        let sessions: ForkClaudeSessionCoordinator
        let chatID: UUID
        let folder: String

        var body: some View {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Claude Code session · \(URL(filePath: folder).lastPathComponent)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if sessions.approvalTool(chatID: chatID) != nil {
                    SymbolImage(name: "exclamationmark.circle.fill", size: Theme.Size.aiChatComposerGlyph)
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityLabel("Claude needs approval")
                }
            }
            .font(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.aiChatComposerControl)
        }
    }

    struct ApprovalNotice: View {
        let sessions: ForkClaudeSessionCoordinator
        let chatID: UUID

        var body: some View {
            if let tool = sessions.approvalTool(chatID: chatID) {
                HStack(spacing: Theme.Spacing.md) {
                    SymbolImage(name: "exclamationmark.circle", size: Theme.Size.aiChatComposerGlyph)
                        .foregroundStyle(Theme.Colors.warning)
                    Text("Claude needs approval: \(tool)")
                        .lineLimit(2)
                    Spacer(minLength: Theme.Spacing.md)
                    Button("Attach") { sessions.openInTerminal(chatID: chatID) }
                        .buttonStyle(.borderless)
                        .disabled(sessions.isBusy(chatID: chatID))
                        .help("Open Claude Code in Terminal to answer the approval")
                }
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
            }
        }
    }

    struct EndedComposer: View {
        let sessions: ForkClaudeSessionCoordinator
        let chatID: UUID

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    SymbolImage(name: "stop.circle", size: Theme.Size.aiChatComposerGlyph)
                    Text("Session ended")
                    Spacer(minLength: Theme.Spacing.md)
                    if let entry = sessions.entry(chatID: chatID),
                        FileManager.default.fileExists(atPath: entry.transcriptPath)
                    {
                        Button("Resume") { sessions.resume(chatID: chatID) }
                            .buttonStyle(.borderless)
                            .disabled(sessions.isBusy(chatID: chatID))
                            .help("Resume this Claude Code session")
                    }
                }
                if let entry = sessions.entry(chatID: chatID) {
                    SessionLabel(sessions: sessions, chatID: chatID, folder: entry.folder)
                }
            }
            .font(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(Theme.Spacing.md)
            .background {
                Color.clear.glassEffect(
                    .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
            }
        }
    }
}
