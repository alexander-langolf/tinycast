import AppKit
import SwiftUI

@MainActor @Observable
final class NotchBarModel {
    var entry = NotchEntry(icon: .ghostty, title: "Ghostty", subtitle: "Not running")
    var applicationIcon: NSImage?
}

struct NotchBarView: View {
    let model: NotchBarModel

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.entry.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                Text(model.entry.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch model.entry.icon {
        case .codex: Image("AIBrandOpenAI").resizable().scaledToFit()
        case .claude: Image("AIBrandClaude").resizable().scaledToFit()
        case .ghostty:
            if let icon = model.applicationIcon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "terminal").resizable().scaledToFit()
            }
        }
    }
}
