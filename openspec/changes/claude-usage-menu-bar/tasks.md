## 1. Endpoint contract

- [x] 1.1 Call `GET /api/oauth/usage` once and record the response shape, units and headers in `design.md`.

## 2. Pure model

- [x] 2.1 Add `ClaudeUsageSnapshot` under `Tinycast/Fork/ClaudeUsage/Model/`: decode known and unknown windows, omit missing windows, and fail closed on a malformed body.
- [x] 2.2 Add window ordering and the label formatter (`42%`, `42% · 18%`, rounding rule) with injected locale and clock.
- [x] 2.3 Add the poll schedule policy: interval constant, conditions for start and stop, wake and manual triggers, 429 skip.
- [x] 2.4 Add harnesses for 2.1 to 2.3 using a fixture built from the shape in `design.md`, and register them in `Scripts/run-tests.sh`.

## 3. Coordinator

- [x] 3.1 Add `ClaudeUsageCoordinator` owned by `AppCore` and wired in `start()`, with a private ephemeral session (`urlCache = nil`) and the 401 single-retry through `ForkClaudeAccount.accessToken(rejectedToken:)`.
- [x] 3.2 Drive polling from the preference and the account phase; drop stale results by generation; cancel the poll task on disable, sign-out and quit.
- [x] 3.3 Store `labelText`, `hasSnapshot`, `lastUpdated` and `lastError`, writing each only when its value changes.

## 4. Menu bar and settings

- [x] 4.1 Add the third `MenuBarExtra` and its insertion binding in `TinycastApp.swift` (`// FORK: claude-usage`), with drag-out writing **Disabled**.
- [x] 4.2 Build `ClaudeUsageMenuBarLabel` and `ClaudeUsageMenuBarMenu`: window rows, last-updated and error lines, **Refresh Now**, **Claude Account Settings…** and the signed-out **Sign In to Claude…**.
- [x] 4.3 Add the **Menu Bar** picker to Claude Account settings, its `SettingsFileKey` and `SettingsFileSchema` binding, and a settings search entry.
- [x] 4.4 Add all new strings to `Localizable.xcstrings` in eight languages and run `./Scripts/sync-strings.sh`.

## 5. Verification and documentation

- [ ] 5.1 Native check (answers Q2): enable each display mode, drag out, sign out and in, sleep and wake, offline, and confirm no requests while disabled.
- [x] 5.2 Write `docs/features/claude-usage.md` with its invariants, and add the hooks to `docs/fork.md`.
- [ ] 5.3 Run `./Scripts/run-tests.sh`, `./Scripts/lint.sh`, the model purity grep, `openspec validate claude-usage-menu-bar`, and a Debug build with no new warnings.
