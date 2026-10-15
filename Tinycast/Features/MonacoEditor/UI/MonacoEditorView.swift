import SwiftUI

/// The panel's content: a slim title bar over the web view, on the same glass as the terminal card.
struct MonacoEditorView: View {
    let session: MonacoEditorSession
    @Environment(MonacoEditorCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @Environment(\.forkColorPreview) private var preview

    private var ink: ForkInk { ForkInk(preview) }

    var body: some View {
        let ink = ink
        VStack(spacing: 0) {
            bar(ink)
            Rectangle().fill(ink.separator).frame(height: 1)
            ZStack {
                MonacoWebView(host: session.host)
                if !session.isReady {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .background { GlassEffectView().allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous))
    }

    private func bar(_ ink: ForkInk) -> some View {
        HStack(spacing: metrics.spacing.md) {
            Image(systemName: "doc.text")
                .foregroundStyle(ink.textSecondary)
            Text(session.document.name)
                .font(metrics.typography.searchField)
                .foregroundStyle(ink.textPrimary)
                .lineLimit(1)
            Circle()
                .fill(ink.textSecondary)
                .frame(width: 7, height: 7)
                .opacity(session.isDirty ? 1 : 0)
                .help("Unsaved changes")
            Spacer(minLength: metrics.spacing.md)
            Text((session.document.path as NSString).deletingLastPathComponent.abbreviatingHome)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(ink.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Button {
                Task { _ = await coordinator.requestClose() }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink.textSecondary)
            .help("Close  ⌘W")
        }
        .padding(.horizontal, metrics.spacing.xl)
        .frame(height: metrics.size.compactHeight)
    }
}

private extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}
