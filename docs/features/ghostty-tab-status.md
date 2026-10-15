# Ghostty tab status

Fork-owned in `Tinycast/Fork/GhosttyStatus/`; `AppCore.ghosttyStatus` owns its coordinator. It
feeds the single entry shown by the [notch bar](notch-bar.md).

## Invariants

- One snapshot tab is one external Ghostty tab, keyed by application launch, window ID and tab ID.
  Split terminal IDs stay nested inside it. Embedded libghostty sessions are excluded.
- The service reads the running Ghostty bundle's scripting dictionary without launching, activating
  or opening anything. PID-addressed Apple Events share `TerminalGhosttyLauncher.scriptQueue` and
  each inventory request has a two-second deadline. It sends `core/getd` object specifiers directly.
  It reads each tab's `selected` flag; the entry uses the first selected tab.
- The bar only reads. The permission check never asks for Automation access, and no tab is selected
  or activated. Closed, denied, unavailable, empty and loaded states stay distinct.
- Polling occurs about every two seconds while the notch bar is expanded, and stops during active
  palette use, sleep and inactive login sessions. Generation and launch identity reject obsolete
  results, and errors clear the tabs.
- Codex or Claude artwork requires a verified live association with one of the tab's terminal IDs.
  Titles and working directories never identify an agent. Where Ghostty exposes terminal `pid` and
  `tty`, the service joins the foreground process group and terminal device to live processes,
  verifies the agent's code signature, and rechecks process identity. Older dictionaries show the
  Ghostty icon only.

## Verification boundary

`ghostty-tab-status-test` compiles the pure model and checks identity, classification and stale-result
rejection. `ghostty-status-lifecycle-test` checks coalescing, cancellation and Apple Event descriptor
construction. `notch-test` covers the entry derived from a snapshot.
