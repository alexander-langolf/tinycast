## Context

`AppCore.start()` unconditionally calls `ghosttyStatus.start()` and `notchBar.start()`. The bar
(`NotchBarCoordinator`) builds a panel and a zero-width `NSStatusItem` probe, observes screen, Space
and sleep notifications, and drives `GhosttyStatusCoordinator` polling through `setResting`. Nothing
else reads `ghosttyStatus`, so the bar is its only consumer.

`NotchBarCoordinator.stop()` is written for app shutdown: it calls `policy.stop()`, and
`NotchPolicy.stop` is terminal (`move(to:)` refuses to leave `.stopped`). `start()` then refuses to
run because of `guard policy.target != .stopped`. A hide followed by a show therefore cannot reuse
`stop()` and `start()`.

Other feature switches in `AppCore` follow one shape: a stored `AppSettings` flag, an
`applyEnabled()` on the owning coordinator, and a `track({ _ = $0.flag }, reproject:)` entry in
`observeFeatureSwitches()`. The proposal and the `notch-bar-visibility` spec set the behaviour.

## Goals / Non-Goals

**Goals:**
- A default-off `notchBarEnabled` preference that shows and hides the bar live.
- A hidden bar costs nothing: no panel, probe, observers or Ghostty polling.
- Follow the existing feature-switch, settings-file and backup conventions exactly.

**Non-Goals:**
- No change to how the bar looks, animates or reads Ghostty while it is visible.
- No per-display choice, no "hide only while a full-screen app is active", no menu-bar item.
- No migration that preserves the old always-on behaviour for existing installs.

## Decisions

**1. A new `notchBarEnabled` flag, default `false`, tracked like the other switches.**
`AppSettings` gains the stored property, `AppSettingsKey` the key, and `observeFeatureSwitches()` a
`track({ _ = $0.notchBarEnabled }, reproject: { $0.notchBar.applyEnabled() })`. The initial pass of
`track` makes launch and live toggling go through the same code path, so there is no second
"start if enabled" branch in `start()`. The two `FORK: notch-bar` lines in `AppCore.start()` become
one call that applies the preference, and `ghosttyStatus.start()` moves under the bar's control.
*Alternative:* read the flag once in `start()`. Rejected: it breaks the live-toggle requirement.

**2. Split "hide" from "stop" on the coordinator.**
`applyEnabled()` calls `show()` or `hide()`. `hide()` tears down everything `start()` created
(observers, appearance observation, backdrop task, probe, panel, surface), stops `ghosttyStatus`, and
resets `policy` to a fresh `NotchPolicy()` so a later `show()` can run. `stop()` stays the terminal
shutdown path called from `AppCore`. `start()` is renamed `show()` only if the name helps readers;
otherwise it is left alone.
*Alternative:* make `NotchPolicy.stop` reversible. Rejected: its terminal state is deliberate, so a
late animation completion can never resurrect a bar during shutdown (`accepts(_:)` depends on it).

**3. The bar owns the Ghostty coordinator's lifetime.**
`show()` calls `core.ghosttyStatus.start()` and `hide()` calls `core.ghosttyStatus.stop()`. The
coordinator already supports `stop()` followed by `start()` (`started` is a plain flag, and `stop()`
publishes `.closed`), so no change is needed inside `GhosttyStatus/`. This is what makes the "no
polling while hidden" requirement true rather than just invisible.
*Alternative:* keep `ghosttyStatus` always started and only stop it from polling. Rejected: it leaves
workspace observers running for a feature the user turned off.

**4. Settings pane placement.**
The toggle goes in the existing settings pane that already hosts fork-owned options, with the same
row component its neighbours use. It lives in the fork folder if that pane is fork-owned, so no
`DesignSystem/` or `Theme` change is needed.

**5. Settings file and backup.**
`SettingsFileKey` gets a case bound in `SettingsFileSchema`; the exhaustive switch fails the build
until it is bound. `SettingsBackupCoverage` classifies it as carried. The flag grants no capability,
so the `snippetsEnabled` exclusion rule does not apply.

**6. Tests.**
Extend `Tests/notch-test.swift` with a policy-reset case: hide then show yields a usable policy, and a
completion identity from before the hide is rejected. Settings schema coverage is enforced by the
existing exhaustive switch and by the settings-file harness.

## Risks / Trade-offs

- [Existing users lose a bar they rely on] → Called out in the proposal as intentional. The release
  note and `docs/features/notch-bar.md` say where the toggle is.
- [`hide()` misses one resource and leaks across toggles] → `hide()` and `stop()` share one teardown
  helper, so the two paths cannot drift. The tests assert a single panel after repeated toggles.
- [The preference turns on while a palette session is open] → `sessionDidStart` is ignored while
  hidden, so a freshly shown bar would sit expanded under an open palette. `show()` reads the
  palette's current visibility and retracts first if it is open.
- [Settings import flips the flag while Tinycast is running] → It goes through the same `track` path
  as a toggle in the UI, so import and UI behave the same.

## Migration Plan

No data migration. An absent key reads as `false`. Rollback is reverting the change; the stored key
is then ignored. Docs updated in the same commit: `docs/features/notch-bar.md` (off by default, how
it is shown and hidden) and `docs/fork.md` if it lists fork preferences.

## Open Questions

- Which settings pane should host the toggle: the General pane, or a fork pane if one exists?
  Check `Tinycast/Features/Settings/` before writing tasks.
- Should the palette's open or closed state be queried from `PaletteWindowController`, or tracked on
  the bar itself, for the "turned on while the palette is open" case?
