import SwiftUI

struct ForkQuickAIRootSettingsRows: View {
    @Environment(AISettingsStore.self) private var aiSettings
    @Environment(InstalledAIManager.self) private var installedAI
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @State private var locatedEngines: Set<ForkQuickAIRootSettings.Engine> = []
    let usesCodex: Bool
    private var settings: ForkQuickAIRootSettings { ForkQuickAIRootSettings.current! }

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.warmRoot) {
                SettingsRowTitle(.quickAIRoot, ForkSettingsSearch.quickAIWarmRootTitle)
                if !usesCodex { Text("Choose Codex as Quick AI's provider to keep a warm root.") }
            }
            .disabled(!usesCodex)
            Picker(selection: $settings.startWorkEngine) {
                ForEach(ForkQuickAIRootSettings.Engine.allCases) { engine in
                    Text(engine.title).tag(engine).disabled(!isInstalled(engine))
                }
            } label: {
                SettingsRowTitle(.quickAIRoot, ForkSettingsSearch.quickAIStartWorkTitle)
            }
            Picker(selection: $settings.retention) {
                ForEach(ForkQuickAIRootSettings.Retention.allCases) { value in
                    Text(value.title).tag(value)
                }
            } label: {
                SettingsRowTitle(.quickAIRoot, ForkSettingsSearch.quickAIRetentionTitle)
            }
        } header: {
            SettingsSectionHeader(.quickAIRoot)
        }
        .task(id: commandPaths) { await locateEngines() }
    }

    private var commandPaths: [String] {
        [InstalledAIKind.claude, .codex].map { aiSettings.override(for: $0).commandPath }
    }

    private func locateEngines() async {
        locatedEngines = []
        var found: Set<ForkQuickAIRootSettings.Engine> = []
        for (engine, kind) in [
            (ForkQuickAIRootSettings.Engine.claude, InstalledAIKind.claude), (.codex, .codex)
        ] {
            let launch = InstalledAILaunch(commandPath: aiSettings.override(for: kind).commandPath)
            switch launch.command() {
            case .executable:
                found.insert(engine)
            case .missing:
                break
            case .automatic:
                let known =
                    kind == .codex
                    ? subscription.executable : installedAI.status(for: kind).executable
                if known != nil {
                    found.insert(engine)
                } else if await ExecutableLocator.locate(
                    kind.command, extraHomePaths: kind.extraExecutablePaths) != nil
                {
                    found.insert(engine)
                }
            }
            guard !Task.isCancelled else { return }
        }
        locatedEngines = found
    }

    private func isInstalled(_ engine: ForkQuickAIRootSettings.Engine) -> Bool {
        guard engine != .off else { return true }
        let kind: InstalledAIKind = engine == .claude ? .claude : .codex
        let commandPath = aiSettings.override(for: kind).commandPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard commandPath.isEmpty else { return locatedEngines.contains(engine) }
        let known =
            kind == .codex
            ? subscription.executable : installedAI.status(for: kind).executable
        return known != nil || locatedEngines.contains(engine)
    }
}
