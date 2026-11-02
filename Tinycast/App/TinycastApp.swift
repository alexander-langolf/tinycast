import SwiftUI

@main
enum TinycastLaunch {
    static func main() {
        clearAgentEnvironment()  // FORK: agent-env
        AppSettings.pinLanguage()
        TinycastApp.main()
    }

    // Agent-launched Tinycast must not hand the agent session to apps it opens.
    private static func clearAgentEnvironment() {
        for name in ProcessInfo.processInfo.environment.keys {
            guard name != "CODEX_HOME",
                name.hasPrefix("CLAUDE") || name.hasPrefix("CODEX_")
            else { continue }
            unsetenv(name)
        }
    }
}

struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

        MenuBarExtra(isInserted: calendarMenuBarInsertion) {
            CalendarMenuBarMenu()
        } label: {
            CalendarMenuBarLabel(appName: appName)
        }

        // FORK: claude-usage
        MenuBarExtra(isInserted: claudeUsageMenuBarInsertion) {
            ClaudeUsageMenuBarMenu().environment(AppCore.shared.claudeUsageCoordinator)
        } label: {
            ClaudeUsageMenuBarLabel(appName: appName).environment(AppCore.shared.claudeUsageCoordinator)
        }
    }

    // FORK: claude-usage
    private var claudeUsageMenuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.claudeUsageCoordinator.settings
        let isInserted = settings.display != .disabled
        return Binding(
            get: { isInserted },
            set: { inserted in
                if inserted {
                    if settings.display == .disabled { settings.display = .usageIcon }
                } else if settings.display != .disabled {
                    settings.display = .disabled
                }
            })
    }

    /// Read in `body` for Observation; SwiftUI echoes the binding back, so only a change writes.
    private var menuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.showInMenuBar
        return Binding(
            get: { isInserted },
            set: { inserted in
                guard inserted != settings.showInMenuBar else { return }
                settings.showInMenuBar = inserted
            })
    }

    /// Writes through `AppSettings`: dragging the item out must stop the clock and move the picker.
    private var calendarMenuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.calendarMenuBarDisplay != .disabled && !isCalendarMenuBarHiddenWhenEmpty
        return Binding(
            get: { isInserted },
            set: { inserted in
                if inserted {
                    guard settings.calendarMenuBarDisplay == .disabled else { return }
                    settings.calendarMenuBarDisplay = .meetingIcon
                } else {
                    // SwiftUI echoes our own removal back; only a drag-out means "turn it off".
                    guard !isCalendarMenuBarHiddenWhenEmpty, settings.calendarMenuBarDisplay != .disabled
                    else { return }
                    settings.calendarMenuBarDisplay = .disabled
                }
            })
    }

    /// Read in `body`, so Observation re-runs the scene when the coordinator's flag flips.
    private var isCalendarMenuBarHiddenWhenEmpty: Bool {
        AppCore.shared.settings.calendarMenuBarHidesWhenEmpty
            && !AppCore.shared.calendarCoordinator.hasMenuBarEvent
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
            Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Window") {
                // The chat window closes itself when it is in front; otherwise ⌘Q is Settings'.
                guard !AppCore.shared.aiChatCoordinator.closeWindowIfKey() else { return }
                AppCore.shared.settingsCoordinator.closeSettings()
            }
            .keyboardShortcut("q")
        }
    }
}
