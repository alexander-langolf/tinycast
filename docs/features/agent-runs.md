# Background agent runs

## Invariants

- **The status snapshot owns card lifetime.** Every returned run is eligible regardless of state;
  a run missing from the next successful snapshot disappears immediately. Nothing is persisted.
- **Polling belongs to palette visibility.** Opening starts an immediate read, then reads every two
  seconds without overlapping within a polling task. `PaletteWindowController` calls the coordinator's
  `paletteDidShow()` / `paletteDidHide()` beside Calendar's lifecycle calls and `palette.noteVisible`.
  `PaletteState.isVisible` remains the visibility flag. Hiding cancels polling but keeps the last
  snapshot, so the next summon shows cards at once while the first poll refreshes them.
  A cancelled read cannot publish into a reopened palette, even if its command finishes later.
- **Process execution goes through `ShellCommandRunner.run`.** AgentRuns requests full stdout with
  `standardOutputLimit: Int.max` so JSON larger than the default 4 KiB is not truncated. Execution,
  output reads and JSON decoding stay off the main actor. The monitor publishes on the main actor
  only when the decoded array changes, like `RunningAppsMonitor`.
- **A failed read keeps the last good snapshot until the next successful read.** Failures go
  to the `AgentRuns` logger; an unavailable helper does not interrupt launcher use.
- **Runs live in a separate, non-activating child panel.** `AgentRunsPanelPresenter` owns its frame
  and attaches it with `addChildWindow`. It is visible only with a visible palette and nonempty
  snapshot, including other palette modes and the compact bar. Cards never enter `PaletteRowIndex`,
  favorites, search results or keyboard navigation, and never take key status or search focus.
- **The stack sits below the palette when it fits the screen's visible frame.** It matches the
  palette width with a 12-point gap. Otherwise it sits top-aligned beside the palette, at 360 points
  wide: right if that fits, left otherwise. Run changes, palette moves, resizes, screen changes and
  Interface Size changes recompute placement. These dimensions use the shared interface scale.
- **At most four run cards stack vertically, with transparent 8-point gaps.** Source order is
  preserved; a smaller `+N more` card counts the rest. Each run card is one launcher row plus vertical padding tall.
  A card without a nonempty `attach` command is display-only.
- **`Model/` is Foundation-only and pure.** `agent-runs-test` compiles the shipped decoding model.
- **`AppCore` owns the monitor, coordinator and panel presenter.** There is no feature singleton,
  settings or cache.

## Data and lifecycle

`AgentRunsMonitor.statusPath` is the single helper-path constant, resolved relative to
`FileManager.default.homeDirectoryForCurrentUser`. `ShellCommandRunner.run` invokes it with
`exec "$1"`, passing the executable path as a positional argument rather than interpolating it into
shell text. Only stdout is decoded as a JSON array of `AgentRun` values:

| Field | Meaning |
| --- | --- |
| `id` | Stable run identity |
| `agent` | `claude`, `subagent` or `codex` |
| `name`, `cwd` | Display name and working directory |
| `state` | Open-ended state string, including `working` and `blocked` |
| `startedAt` | Integer epoch milliseconds |
| `last`, `attach`, `model` | Optional strings; omitted and null both decode as absent. `model` is a short name such as "Opus" or a Codex model id |

`AgentRunsCoordinator.paletteDidShow()` starts the monitor and `paletteDidHide()` stops it, following
Calendar's lifecycle for both explicit hiding and focus-loss dismissal. The child panel follows
palette visibility in every mode. Termination stops the coordinator and its monitor. The shared
runner lets an in-flight command finish after cancellation; cancellation checks and the monitor's
publish guard prevent its result from replacing the retained snapshot, including after reopening.

`ShellCommandRunner.run` keeps up to 4 KiB of stdout when `standardOutputLimit` is omitted or nil.
AgentRuns passes `Int.max` for complete JSON; the 8 KiB stderr limit and streaming path are unchanged.

## Presentation and attachment

`Windows/AgentRuns/AgentRunsPanel` hosts `AgentRunsStack` with a transparent root and no shared
background. `AgentRunsPanelPresenter` owns the child, run-count observation and all placement;
`PaletteWindowController` only forwards lifecycle and geometry events through tagged fork hooks.
`LauncherList` and the palette's own dimensions stay unchanged. If neither side has enough space,
the left placement is clamped to the screen's visible frame, which can overlap the palette.

Each card uses `PaletteBackground`'s behind-window material, adaptive scrim and edge treatment,
clipped to the palette's continuous corner radius. The transparent panel supplies native shadows
around the card silhouettes. `AgentRunsMetrics` keeps the feature's 360-point side width and 6-point
status dot local, scaled through `InterfaceMetrics.scaled`. Existing Theme tokens and
`InterfaceMetrics` supply the shared typography and geometry:
run cards are `rowIcon + sm * 2` plus `sm` above and below (48 points at standard size, `AgentRunsMetrics.cardHeight`, shared by the card and the panel frame), and the overflow card is
`barButtonHeight` (28 points). Working uses the accent dot, blocked uses warning orange, and other
states use tertiary ink; accessibility also reads the state. Names and secondary activity each
truncate to one line; a missing activity leaves that line empty. The trailing agent kind (followed by the model, in tertiary text, when known) and live
elapsed duration use secondary text. A one-second `TimelineView` uses `CommandDuration.text` and
monospaced digits, matching command output and ticking independently of snapshot publication.

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

## Editing the cards visually

Open `Tinycast.xcodeproj` in Xcode, open `Features/AgentRuns/UI/AgentRunCard.swift`, and open the
canvas with ⌥⌘↩. The previews live in `AgentRunsPreviewData.swift` (`#if DEBUG`, so none of it ships
in Release): one card per state (working, blocked, done), Codex and no-model runs, a long title and
detail line, and a four-card stack. They need no AppCore: the cards read only the default
`InterfaceMetrics`, and the stack gets a coordinator over a fixed `AgentRunsMonitor(previewRuns:)`.
Edit sizes in `AgentRunsMetrics` or the card and watch the canvas update. After adding a Swift file on
disk, run `xcodegen generate` so the project picks it up.

## Fork ownership

`Features/AgentRuns/`, `Windows/AgentRuns/`, this document and `Tests/agent-runs-test.swift` are
fork-owned. Shared design-system files and upstream feature documentation carry no AgentRuns edits.
The small integration hooks are listed in [the fork guide](../fork.md#upstream-hooks); the generated
Xcode project includes the feature sources. `Scripts/run-tests.sh` registers the decoding harness.
