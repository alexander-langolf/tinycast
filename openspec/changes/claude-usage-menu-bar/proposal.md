## Why

Claude plan limits are visible only inside Claude Code's `/usage` screen. Hitting the five-hour or
weekly limit mid-task is the first sign most sessions get. Tinycast already signs in to the Claude
account and already runs a status item for the calendar, so it can show the same numbers at a glance.

## What Changes

- Add a third independent `MenuBarExtra` for Claude plan usage, next to Tinycast's own item and the
  calendar item. One preference inserts it, and it reads nothing off the other two.
- The item's label shows the five-hour session utilisation, optionally followed by the weekly
  utilisation, or only an icon.
- The item's menu lists every usage window the account reports, each with its percentage and reset
  time, plus **Refresh Now** and **Claude Account Settings…**.
- A `ClaudeUsageCoordinator` owned by `AppCore` fetches `GET https://api.anthropic.com/api/oauth/usage`
  with the existing `ForkClaudeAccount` access token. It polls only while the item is inserted and the
  account is signed in.
- Claude Account settings gain a **Menu Bar** picker with **Disabled**, **Usage Icon**, **Session
  Percent** and **Session and Week**. The preference gets a `SettingsFileKey`.
- Signed out, the item shows the icon and a **Sign In to Claude…** menu entry.

## Capabilities

### New Capabilities

- `claude-usage-menu-bar`: The Claude usage status item covers its insertion preference, label
  formats, menu contents, polling lifecycle, signed-out state and failure behaviour.

### Modified Capabilities

None. The Tinycast and calendar items keep their requirements.

## Impact

- New fork folder `Tinycast/Fork/ClaudeUsage/` with an AppKit-free `Model/` for the response decoder,
  window ordering and label formatting, plus the coordinator and the SwiftUI label and menu.
- `Tinycast/App/TinycastApp.swift` gains a third scene and its insertion binding, marked
  `// FORK: claude-usage`.
- `Tinycast/App/AppCore.swift` owns and starts the coordinator, marked `// FORK: claude-usage`.
- `Tinycast/Fork/ClaudeAccount/` gains the settings row and exposes the signed-in phase the
  coordinator observes.
- `Localizable.xcstrings` gains the new strings in all eight languages.
- `SettingsFileSchema` binds the new key.
- `Scripts/run-tests.sh` registers the new harnesses.
- `docs/fork.md` lists the new hooks, and a new `docs/features/claude-usage.md` holds the invariants.
- The usage endpoint is undocumented and private to Claude Code. Its shape can change without notice.
- No new dependency.
