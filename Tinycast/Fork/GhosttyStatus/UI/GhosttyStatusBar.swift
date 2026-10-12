import AppKit
import SwiftUI

struct GhosttyStatusBar: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.forkColorPreview) private var preview
    let coordinator: GhosttyStatusCoordinator
    let state: GhosttyStatusState
    let width: CGFloat
    let height: CGFloat
    let openLauncher: () -> Void
    let showOverflow: () -> Void
    let tooltip: (String?, CGRect) -> Void

    private var layout: GhosttyStatusMetrics { GhosttyStatusMetrics(metrics: metrics) }
    private var inventory: GhosttyTabInventory? {
        if case .loaded(let inventory) = state { return inventory }
        return nil
    }

    var body: some View {
        let tabs = inventory?.tabs ?? []
        let generic = inventory?.capability == .tabsOnly
        let reserved = generic ? layout.icon + layout.gap : 0
        let fitted = layout.fit(count: tabs.count, width: width - reserved)
        let ink = ForkInk(preview, theme: layout.cards.theme)
        HStack(spacing: layout.gap) {
            if tabs.isEmpty {
                emptyState.font(layout.cards.titleFont).foregroundStyle(ink.textSecondary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(tabs.prefix(fitted.visibleCount)) { tab in
                    GhosttyStatusCard(
                        tab: tab, agent: tab.agentKind(associations: inventory?.associations ?? [:]),
                        icon: coordinator.applicationIcon, height: height - layout.inset * 2,
                        width: layout.cardWidth, tooltip: tooltip
                    ) { coordinator.select(tab) }
                }
                if fitted.overflowCount > 0 {
                    Button("+\(fitted.overflowCount)", action: showOverflow)
                        .font(layout.cards.trailingFont).buttonStyle(.plain)
                        .frame(width: layout.overflowWidth, height: height - layout.inset * 2)
                        .accessibilityLabel("Show \(fitted.overflowCount) more Ghostty tabs")
                        .modifier(GhosttyStatusTooltip(text: "Show more Ghostty tabs", hover: tooltip))
                }
                Spacer(minLength: 0)
            }
            if generic {
                Image(systemName: "info.circle")
                    .font(metrics.typography.keyCap).frame(width: layout.icon)
                    .accessibilityLabel(Self.capabilityExplanation)
                    .modifier(GhosttyStatusTooltip(text: Self.capabilityExplanation, hover: tooltip))
            }
            Button(action: openLauncher) {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
                    .frame(width: layout.icon, height: layout.icon)
            }
            .buttonStyle(.plain)
            .frame(width: layout.launcherWidth, height: height - layout.inset * 2)
            .accessibilityLabel("Open Tinycast")
            .modifier(GhosttyStatusTooltip(text: "Open Tinycast", hover: tooltip))
        }
        .padding(.horizontal, layout.inset)
        .frame(width: width, height: height)
        .background {
            layout.cards.shape.fill(layout.cards.scrim(ink))
                .background(GlassEffectView().clipShape(layout.cards.shape))
        }
        .overlay { AgentRunCardBorder(layout: layout.cards, ink: ink) }
        .contentShape(layout.cards.shape)
    }

    static let capabilityExplanation =
        "This Ghostty build cannot identify agents. Agent icons require terminal PID and TTY support."

    @ViewBuilder private var emptyState: some View {
        switch state {
        case .closed: Text("Ghostty closed")
        case .empty: Text("No Ghostty tabs")
        case .unavailable: Text("Ghostty unavailable")
        case .permissionRequired:
            Button("Allow Ghostty access") { coordinator.requestPermission() }
                .buttonStyle(.plain)
                .modifier(
                    GhosttyStatusTooltip(
                        text: "Allow Tinycast to read and select Ghostty tabs", hover: tooltip))
        case .loaded: EmptyView()
        }
    }
}

struct GhosttyStatusCard: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.forkColorPreview) private var preview
    let tab: GhosttyTabSnapshot
    let agent: GhosttyAgentKind?
    let icon: NSImage?
    let height: CGFloat
    let width: CGFloat
    let tooltip: (String?, CGRect) -> Void
    let select: () -> Void

    var body: some View {
        let layout = GhosttyStatusMetrics(metrics: metrics)
        let ink = ForkInk(preview, theme: layout.cards.theme)
        Button(action: select) {
            HStack(spacing: layout.gap) {
                brandIcon.frame(width: layout.icon, height: layout.icon)
                Text(tab.description).font(layout.cards.titleFont).foregroundStyle(ink.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.padding)
            .frame(width: width, height: height)
            .background(layout.cards.scrim(ink))
            .background(GlassEffectView())
            .clipShape(layout.cards.shape)
            .overlay { AgentRunCardBorder(layout: layout.cards, ink: ink) }
            .contentShape(layout.cards.shape)
        }
        .buttonStyle(.plain).focusable(false)
        .modifier(GhosttyStatusTooltip(text: tab.description, hover: tooltip))
        .accessibilityLabel("Select Ghostty tab: \(tab.description)")
    }

    @ViewBuilder private var brandIcon: some View {
        switch agent {
        case .codex: Image("AIBrandOpenAI").resizable().scaledToFit()
        case .claude: Image("AIBrandClaude").resizable().scaledToFit()
        case nil:
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "terminal").resizable().scaledToFit()
            }
        }
    }
}
