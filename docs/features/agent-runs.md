# Background agent runs

## Invariants

- **The status snapshot owns card lifetime.** Every returned run is eligible regardless of state;
  a run missing from the next successful snapshot disappears immediately. Nothing is persisted.
- **Polling belongs to palette visibility.** Opening starts an immediate read, then reads every two
  seconds without overlapping. Hiding cancels the task and its in-flight process and clears all runs.
  A cancelled read cannot publish into a reopened palette.
- **Process execution, pipe reads and JSON decoding stay off the main actor.** The monitor publishes
  on the main actor only when the decoded array changes, like `RunningAppsMonitor`.
- **A failed read keeps the last good snapshot until the next successful read or hide.** Failures go
  to the `AgentRuns` logger; an unavailable helper does not interrupt launcher use.
- **The footer is outside the launcher scroll view and selection model.** Cards never enter
  `PaletteRowIndex`, favorites, search results or keyboard navigation. There is no footer for an empty
  snapshot, a hidden palette, another palette mode or the collapsed compact bar.
- **At most three cards occupy one fixed-height row.** Source order is preserved; `+N more` counts
  the rest. A card without a nonempty `attach` command is display-only.
- **`Model/` is Foundation-only and pure.** `agent-runs-test` compiles the shipped decoding model.
- **`AppCore` owns the monitor and coordinator.** There is no feature singleton, settings or cache.

## Data and lifecycle

`AgentRunsMonitor.statusPath` is the single helper-path constant, resolved relative to
`FileManager.default.homeDirectoryForCurrentUser`. The executable is invoked directly, without shell
interpolation. Only stdout is decoded as a JSON array of `AgentRun` values:

| Field | Meaning |
| --- | --- |
| `id` | Stable run identity |
| `agent` | `claude`, `subagent` or `codex` |
| `name`, `cwd` | Display name and working directory |
| `state` | Open-ended state string, including `working` and `blocked` |
| `startedAt` | Integer epoch milliseconds |
| `last`, `attach` | Optional strings; omitted and null both decode as absent |

`AppCore.start()` wires `PaletteWindowController.onVisibilityChanged` to the monitor. The callback
covers both explicit hiding and focus-loss dismissal. Polling continues while the palette is visible
in another mode, but only the expanded launcher renders the footer. Termination stops the monitor
and coordinator. The cancellation handle serializes process launch with cancellation so hiding
cannot race a new subprocess into existence after the cancellation check.

## Presentation and attachment

`LauncherList` adds `AgentRunsFooter` as a transparent bottom safe-area inset above the palette's
existing action bar. It uses the existing edge dissolve and does not change the window frame.
The cards are 96 points high at standard Interface Size, scale through `InterfaceMetrics`, and
use Theme typography, adaptive fills and continuous corners. Working uses the accent color,
blocked uses warning orange, and other states use tertiary ink; accessibility also reads the state.
The elapsed timer is SwiftUI's live timer text, independent of snapshot publication. Names,
activity and paths each stay on one line; a missing activity leaves that line empty.

An attachable card calls `AgentRunsCoordinator.attach(_:)`, which checks that the card still belongs
to the current snapshot. `AgentRunLauncher` opens `/Applications/kitty.app` through `NSWorkspace`
with `createsNewApplicationInstance`, its working directory and `/bin/zsh -lc` followed by the exact
command as a separate argument. Paths are never interpolated into shell text. Opening failures use
Tinycast's existing message HUD. Showing kitty dismisses the palette through normal focus loss.

## Verification

The registered `Tests/agent-runs-test.swift` harness covers all three kinds, source order, epoch
milliseconds, omitted/null fields, unknown states, equality changes and malformed input.
Manual verification should cover appearance and Interface Size, zero/one/three/many runs, a removed
run, live activity updates, hide/reopen during a poll, missing or failing helpers, and kitty attachment
with spaces in the working directory. Also check that arrow keys and Return still act on launcher
rows while the footer changes.
