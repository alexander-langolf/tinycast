## Why

The resting launcher is a floating card strip detached from the screen edge, and the active launcher
carries an Agent Runs card stack beside it. Both read as clutter. The status surface should instead
feel like part of the hardware: a notch that slides out of the top edge, in the style of Droppy, and
retracts when the launcher is invoked.

## What Changes

- **BREAKING** Rewrite the resting presentation from `notch-status-bar`: the floating, centred card
  strip is replaced by a notch-anchored bar attached to the top screen edge. The earlier change's
  compact cards, `+N` overflow list, permission row and tab-selection clicks are removed.
- Remove the Agent Runs card stack from the main (active) launcher view. The Agent Runs feature itself
  and its settings stay; only its presentation beside the launcher goes.
- Remove the animation that carries the launcher field to and from the resting bar: no travelling
  header snapshot, no uniform scale, no frame interpolation. The active launcher appears and
  disappears exactly as it did before the persistent field existed.
- Add a notch slide: the bar grows down out of the top edge, from the notch's footprint to a wider
  panel with concave shoulders where it meets the screen top. When the launcher is invoked, the
  animation plays in reverse (bar retracts into the notch); on dismissal it slides out again.
- The settled bar shows one status entry: an icon, a title and a one-line subtitle, in the layout of
  the reference image. Content comes from the existing Ghostty tab status service.
- Surface colour follows the menu bar. Use a menu-material blur so a translucent menu bar makes the
  notch read as part of it; do not use a fixed black fill.
- Non-notched and external displays get a centred virtual notch of the same width. The bar uses the
  main screen.
- The bar is not clickable for now: it ignores mouse events and exposes no actions.

## Capabilities

### New Capabilities

- `notch-status-surface`: Notch-anchored slide-out status bar: geometry and concave shape, menu-material
  appearance, slide in/out and reverse-on-invoke behaviour, virtual notch, main-screen placement,
  non-interactivity, and the single icon/title/subtitle entry.

### Modified Capabilities

- `ui`: The launcher no longer shows Agent Runs cards, and no longer animates between a resting field
  and the active palette. Show and hide revert to the pre-persistent-field behaviour.

## Impact

- `Tinycast/Fork/Palette/`: `PersistentLauncherCoordinator`, `PersistentLauncherGeometry`,
  `PersistentLauncherHeader` and `PersistentLauncherPolicy` are rewritten or deleted; the header
  snapshot and frame-flight machinery and their harnesses go.
- `Tinycast/Fork/GhosttyStatus/UI/`: `GhosttyStatusBar` and its metrics, tooltip and overflow list are
  replaced by the single-entry notch view. The inventory service, coordinator and process reader are
  reused; the `+N` overflow and permission-row UI are dropped.
- `Tinycast/Windows/AgentRuns/` presenter and the `PaletteWindowController` / `PaletteEnvironment`
  hooks that attach the card stack.
- AppKit panel at the top edge, screen-safe-area and `auxiliaryTop*` notch geometry, and an
  `NSVisualEffectView` menu material. No new dependency.
- Docs: `docs/features/persistent-launcher-field.md`, `ghostty-tab-status.md`, `agent-runs.md`,
  `docs/fork.md` and the notch verification record.
- The earlier `notch-status-bar` change is superseded; archive it without syncing its specs.
