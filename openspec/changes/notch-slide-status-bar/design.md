## Context

`persistent-launcher-field` and `notch-status-bar` produced a passive floating panel that rests as a
card strip 4 points below the top edge and, on invocation, animates a snapshot of the launcher header
(scale 0.5 to 1.0, frame interpolation) into the real palette. That machinery is about 750 lines
across `Tinycast/Fork/Palette/` plus the `GhosttyStatus` card UI, and it is the source of the
focus/snapshot invariants in `docs/features/persistent-launcher-field.md`.

The new behaviour is much simpler: the launcher shows and hides as before, and an independent,
non-interactive notch bar slides out of the top edge when no session is active and retracts when one
starts. The two surfaces no longer hand content to each other, so the travelling snapshot, the
rendering mask, held-display logic and cross-display relocation can all go.

Droppy is the visual reference. Its repository is DMCA-blocked and its installed binary does not
reveal how it colours the notch, so nothing here is derived from its source. Droppy's notch is solid
black; the menu-bar-matching fill is this project's own requirement.

## Goals / Non-Goals

**Goals:**

- A notch-anchored bar that expands from and retracts into the notch, reading as part of the menu bar.
- Launcher show/hide identical to its pre-persistent behaviour, with focus guarantees intact.
- Delete the snapshot/flight machinery rather than leave it dormant.

**Non-Goals:**

- Any click, hover or keyboard interaction with the bar.
- Tab selection, overflow list, permission prompts or multi-entry layout.
- Other displays than the main one, or other content providers.
- Changing the Ghostty inventory service, its permission handling or its agent-detection contract.

## Decisions

### 1. Rewrite, not extend, the persistent launcher

Replace `PersistentLauncherCoordinator` with a much smaller `NotchBarCoordinator`, still owned by
`AppCore`. Its state is a pure two-phase policy (expanded or retracted, plus a transition identity
for stale-completion rejection), fed by the existing logical session start and end. Delete
`PersistentLauncherHeader`, the header capture, `setRenderingHidden`, `Flight`/`CADisplayLink`
stepping, `travellingResting`, `interpolate` and their harnesses. `PalettePresentation` and the
resolver are reviewed for what still has a caller; unused ones are deleted, not kept as wrappers.

`PaletteWindowController` returns to showing and hiding the real palette directly. The
"logical activity versus physical visibility" split stays only where other consumers already depend
on it; a follow-up audit task checks each row of the existing visibility table.

Alternative: keep the coordinator and bolt a notch shape onto the resting panel. Rejected because the
guarantees it carries (frozen snapshots, native editor continuity during travel) exist only for the
travel being removed.

### 2. Geometry from the display, with a virtual notch

Notch footprint comes from `NSScreen.safeAreaInsets.top` for height and from the gap between
`auxiliaryTopLeftArea` and `auxiliaryTopRightArea` for width. Without a notch (those are nil or the
inset is zero) use a virtual notch of a fixed nominal width and the menu bar height. Target
`NSScreen.main`; recompute on screen-parameter and main-display notifications through observers owned
by the coordinator. A pure `NotchGeometry` model takes these numbers as parameters (no AppKit) and
returns the collapsed and expanded frames and the shoulder radius, so it is covered by a harness.

The expanded size is a fixed width and a height derived from the content metrics at the current
interface size, clamped to the display. The shape is a path: flat top on the screen edge, concave
shoulder arcs outward at the top corners, rounded lower corners. It is applied as a layer mask so
one path is interpolated between collapsed and expanded rather than two views being cross-faded.

Alternative: draw the shape with SwiftUI. Rejected in favour of one `CAShapeLayer` mask because the
path is animated with `CABasicAnimation` and the panel hosts a single `NSVisualEffectView`.

### 3. Menu-material fill

One `NSVisualEffectView` with `.menu` material and `.behindWindow` blending fills the shape, so a
translucent menu bar and the notch bar sample the same backdrop. The panel's appearance is taken from a zero-width `NSStatusItem` button's `effectiveAppearance`, because
the menu bar can render dark under a light system appearance (wallpaper tint) and the app's own
appearance then picks the wrong material. Text uses the semantic label colours.

A material blur samples whatever window is behind the bar, so over a bright page it turns grey while the
menu bar stays on the wallpaper. The primary fill is therefore the wallpaper's average colour over the menu
bar band, read from the desktop image file (no permission); the material is the fallback for Reduce
Transparency or an unreadable wallpaper. Measured on a dark wallpaper: menu bar (0,14,36), sampled fill
(0,15,38). The hardware notch is always black, so a seam can still show.

Alternative: capture the screen strip behind the menu bar. Rejected: needs Screen Recording permission.
Reading the wallpaper file avoids it, at the cost of ignoring menu bar tinting over wallpapers that vary.

### 4. Panel: above the menu bar, mouse-transparent

A fresh `NSPanel` subclass (borderless, non-activating, `canBecomeKey/Main` false) at a level above
the menu bar, `ignoresMouseEvents = true`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`,
no shadow. The level that clears the menu bar and the notch region must be verified at runtime;
`.palette` (current) sits below it. The panel is created once at startup, its frame fixed at the
expanded size, with only the mask path and content opacity animating, so no window resizing occurs
during the slide. Fullscreen Spaces hide the menu bar, so the bar follows system behaviour there and
the check is recorded rather than forced.

### 5. Animation and ordering

Expand: animate the mask path collapsed to expanded over a fixed, non-bouncing duration, then fade
content in. Retract: fade content out, then animate the path back. Retract starts synchronously on the
logical session start, in the same turn as the palette show, and is independent of palette focus
setup, so the launcher's focus path is untouched. The coordinator rejects completions whose
transition identity is stale and retargets from the presentation layer's current path on reversal.
Reduce Motion skips the path animation and uses a fade of at most 0.15 seconds. No display link is
used; Core Animation owns the interpolation.

### 6. Single content entry from the existing service

A small SwiftUI view hosted in the panel renders icon, title and subtitle from a pure
`NotchEntry` derived from `GhosttyStatusCoordinator`'s snapshot: the selected tab of the frontmost
window, agent icon only with a verified association, else the Ghostty icon, working-directory
basename as subtitle. Remove the card, overflow, tooltip, permission-row and metrics UI. The service
stays but its selection (`click`) entry point loses its only caller and is deleted rather than left;
the passive no-prompt permission check stays so unavailable states render neutrally. The view is
read-only and carries no controls.

Open point carried into tasks: whether the service already exposes "selected tab of frontmost
window" or only an ordered tab list; if only the latter, the pure entry model derives it.

## Risks / Trade-offs

- [Menu material does not match the real menu bar exactly, and the hardware notch is pure black] →
  Verify on the notched display in light and dark and over varied wallpapers; adjust tint or material
  based on that check, and record the residual difference.
- [Panel level above the menu bar covers menu extras or other system UI] → Keep the bar within the
  notch-centred footprint, verify it never overlaps menu bar items, and test Mission Control and fullscreen.
- [Deleting the snapshot machinery regresses a focus guarantee the visibility table protected] →
  Re-audit each table row; keep the lifecycle harnesses and delete only travel-specific ones.
- [Retract and palette show race on rapid toggle] → Transition identity plus presentation-layer
  retargeting, with a pure policy harness for reversal and stale completion.
- [Single entry hides other tabs] → Accepted for this change; not clickable by request.

## Migration Plan

1. Add `NotchGeometry`, the pure policy and entry model with harnesses.
2. Add the notch panel, mask animation and content view behind `NotchBarCoordinator`; wire it in
   `AppCore` in place of the persistent launcher.
3. Revert palette show/hide to direct presentation; remove the Agent Runs presenter hooks.
4. Delete the unused travel, snapshot and card code and their harnesses; update docs and the fork audit.
5. Run the full repository checks and native acceptance. Rollback is reverting the change; no settings
   or persisted data are touched.

## Open Questions

- Expanded dimensions and shoulder radius: start from the reference image (about 420 by 82 points at
  its scale) and tune on device.
- Whether `.menu` material alone is close enough, or needs a tint layer, is decided by the on-device check.
