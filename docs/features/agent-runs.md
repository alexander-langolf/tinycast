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
- **Runs live in a separate, non-activating child panel.** `PaletteWindowController` owns its frame
  and attaches it with `addChildWindow`. It is visible only with a visible palette and nonempty
  snapshot, including other palette modes and the compact bar. Cards never enter `PaletteRowIndex`,
  favorites, search results or keyboard navigation, and never take key status or search focus.
- **The stack sits below the palette when it fits the screen's visible frame.** It matches the
  palette width with a 12-point gap. Otherwise it sits top-aligned beside the palette, at 360 points
  wide: right if that fits, left otherwise. Run changes, palette moves, resizes, screen changes and
  Interface Size changes recompute placement. These dimensions use the shared interface scale.
- **At most four run cards stack vertically, with transparent 8-point gaps.** Source order is
  preserved; a smaller `+N more` card counts the rest. Each run card is one launcher row tall.
  A card without a nonempty `attach` command is display-only.
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
covers both explicit hiding and focus-loss dismissal. The child panel follows palette visibility
in every mode. Termination stops the monitor and coordinator. The cancellation handle serializes
process launch with cancellation so hiding cannot race a new subprocess into existence after the
cancellation check.

## Presentation and attachment

`Windows/AgentRuns/AgentRunsPanel` hosts `AgentRunsStack` with a transparent root and no shared
background. The palette controller owns the child and all placement; `LauncherList` and the palette's
own dimensions stay unchanged. If neither side has enough space, the left placement still applies;
the stack never shifts back over the palette to clamp itself onto the screen.

Each card uses `PaletteBackground`'s behind-window material, adaptive scrim and edge treatment,
clipped to the palette's continuous corner radius. The transparent panel supplies native shadows
around the card silhouettes. Theme tokens and `InterfaceMetrics` supply its typography and geometry:
run cards are `rowIcon + sm * 2` (36 points at standard size), and the overflow card is
`barButtonHeight` (28 points). Working uses the accent dot, blocked uses warning orange, and other
states use tertiary ink; accessibility also reads the state. Names and secondary activity each
truncate to one line; a missing activity leaves that line empty. The trailing agent kind and live
elapsed timer use secondary text. SwiftUI's timer updates independently of snapshot publication.

An attachable card calls `AgentRunsCoordinator.attach(_:)`, which checks that the card still belongs
to the current snapshot. `AgentRunLauncher` opens `/Applications/kitty.app` through `NSWorkspace`
with `createsNewApplicationInstance`, its working directory and `/bin/zsh -lc` followed by the exact
command as a separate argument. Paths are never interpolated into shell text. Opening failures use
Tinycast's existing message HUD. The child accepts clicks without becoming key or main, and its
buttons cannot take keyboard focus. Showing kitty dismisses the palette through normal focus loss.

## Verification

The registered `Tests/agent-runs-test.swift` harness covers all three kinds, source order, epoch
milliseconds, omitted/null fields, unknown states, equality changes and malformed input.
Manual verification should cover appearance and Interface Size, zero/one/four/many runs, a removed
run, live activity updates, hide/reopen during a poll, missing or failing helpers, and kitty attachment
with spaces in the working directory. Also check that arrow keys and Return still act on launcher
rows while the stack changes. Check below/right/left placement near screen edges, moves and resizes,
compact mode and other palette modes, transparent gaps and shadows over a light desktop, and search
focus through card mouse-down until attachment activates kitty.
