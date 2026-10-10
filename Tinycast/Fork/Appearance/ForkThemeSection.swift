import SwiftUI

/// One component's tokens under its own header, an optional live preview first and a reset last.
struct ForkThemeSection<Preview: View>: View {
    let component: ForkThemeToken.Component
    @ViewBuilder var preview: Preview
    private var store: ForkThemeStore { ForkThemeStore.current! }

    var body: some View {
        Section {
            preview
            ForEach(component.tokens, id: \.self) { token in
                ForkThemeTokenRow(token: token)
            }
            HStack {
                Spacer()
                Button("Reset \(component.title)") { store.reset(component) }
                    .disabled(!store.tokens.hasOverrides(in: component))
            }
        } header: {
            SettingsSectionHeader(.appearance(component))
        }
    }
}

extension ForkThemeSection where Preview == EmptyView {
    init(component: ForkThemeToken.Component) {
        self.init(component: component) { EmptyView() }
    }
}
