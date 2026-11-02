import SwiftUI

struct ClaudeUsageMenuBarMenu: View {
    @Environment(ClaudeUsageCoordinator.self) private var coordinator
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        Group {
            if coordinator.isSignedIn {
                if let snapshot = coordinator.snapshot {
                    Section {
                        ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                            let name = ClaudeUsageFormat.windowTitle(window, locale: locale)
                            let percent = ClaudeUsageFormat.percent(window.percent, locale: locale)
                            let reset = ClaudeUsageFormat.reset(window.resetsAt, locale: locale, timeZone: timeZone)
                            Text("\(name): \(percent) · resets \(reset)")
                        }
                    }
                }
                if let error = coordinator.lastError {
                    Section {
                        if let updated = coordinator.lastUpdated {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(ClaudeUsageFormat.updated(updated, now: context.date, locale: locale))
                            }
                        }
                        Text(error)
                    }
                }
            } else {
                Button("Sign In to Claude…", action: coordinator.signIn)
            }
            Section {
                Button("Refresh Now", action: coordinator.refresh)
                    .disabled(!coordinator.isSignedIn)
                Button("Claude Account Settings…", action: coordinator.openAccountSettings)
            }
        }
    }
}
