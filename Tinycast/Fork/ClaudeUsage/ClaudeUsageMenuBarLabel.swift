import SwiftUI

struct ClaudeUsageMenuBarLabel: View {
    let appName: String
    @Environment(ClaudeUsageCoordinator.self) private var coordinator

    var body: some View {
        if coordinator.hasSnapshot, !coordinator.labelText.isEmpty {
            Text(verbatim: coordinator.labelText)
                .accessibilityLabel(Text("\(appName): Claude usage, \(coordinator.labelText)"))
        } else {
            SymbolImage(name: "gauge.with.dots.needle.50percent", size: Theme.Size.menuIcon)
                .accessibilityLabel(Text("\(appName): Claude usage"))
        }
    }
}
