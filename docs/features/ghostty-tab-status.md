# Ghostty tab status

Fork-owned in `Tinycast/Fork/GhosttyStatus/`; `AppCore.ghosttyStatus` owns its coordinator.
The status bar replaces the resting persistent launcher's search preview. The active launcher
keeps its normal search field and focus sequence.

## Invariants

- One card represents one external Ghostty tab, keyed by application launch, window ID and tab ID.
  Split terminal IDs stay nested inside that card. Embedded libghostty sessions are excluded.
- The service reads the running Ghostty bundle's scripting dictionary without launching, activating
  or opening anything. PID-addressed Apple Events share `TerminalGhosttyLauncher.scriptQueue` and
  each inventory or selection request has a two-second deadline. It sends `core/getd` object
  specifiers directly; it does not execute AppleScript source. Selection rechecks the live
  application, window and tab IDs before selecting an existing tab and activating its window.
- Passive permission checks never request Automation access. The permission row requests it only
  when clicked. Closed, denied, unavailable, empty and loaded states have distinct presentations;
  errors remove actionable cards.
- Polling occurs about every two seconds at rest, stops during active palette use, sleep and inactive
  login sessions, and resumes on return. Generation and launch identity reject obsolete results.
- Compact cards use the agent-card surface and type tokens. The full title remains in help and the
  accessibility label; visible text truncates. Overflow opens a Tinycast-owned list. Tab clicks select
  Ghostty; the separate Tinycast control invokes the launcher.
- Codex or Claude artwork requires a verified live association with one of the tab's terminal IDs.
  Titles and working directories never identify an agent. Where Ghostty exposes terminal `pid` and
  `tty`, the service joins the foreground process group and terminal device to live processes,
  verifies the agent's code signature, and rechecks process identity and terminal association.
  Older dictionaries without those properties show ordinary Ghostty cards and explain the limit
  through the information control. The running target in the accepted native retest exposed these
  properties and showed verified Codex and Claude icons without an information control.

## Verification boundary

`ghostty-tab-status-test` compiles the shipped pure model and checks tab identity, split-terminal
classification, misleading titles and bounded layout. `ghostty-status-lifecycle-test` checks
coalescing, cancellation, obsolete results and native Apple Event descriptor construction.
`persistent-launcher-input-test` guards the native editor during presentation travel. A signed
Debug build checks Swift 6 integration. Native retest confirmed two actual Ghostty tabs and verified
Codex and Claude icons. Tab selection, overflow, updates and physical hotkey focus were confirmed by
the user; all three interface sizes were inspected. See
[the verification record](../notch-status-bar-verification.md) for results and untested native scenarios.
