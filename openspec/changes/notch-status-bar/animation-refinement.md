# Launcher animation refinement

User request: move and scale the actual launcher field, then swap to the status bar at the end.

## Design

Use a captured rendering of the current launcher header throughout travel. Closing retains the
field's content and aspect ratio as it shrinks to half size at the top anchor; the status cards appear
only after arrival. Opening performs the inverse handoff at the top and moves the scaled field into
the active position. The native editor retains synchronous focus and live typing during opening.
Do not stretch or move the status-card layout through the flight. Keep Reduce Motion immediate and
preserve rapid reversals and current-frame retargeting. Avoid changing unrelated motion tokens.

## Implementation plan

- [x] Trace capture/hide ordering in `PersistentLauncherCoordinator` and `PaletteWindowController`;
  capture the closing header before its native content is reset or hidden.
- [x] Preserve uniform field scaling and perform the status-content swap at arrival, including
  opening, closing, interruption, Reduce Motion and different status/header heights.
- [x] Extend the native launcher harness to check closing snapshot retention, status timing and
  input continuity; remove obsolete opacity interpolation if no longer used.
- [x] Update affected OpenSpec/UI docs, run required checks and the signed canonical Debug build.
- [x] Parent restarts only the canonical Dev instance for native review; the user confirmed the
  revised movement feels better, and native typing/dismissal passed.

No commit or push is part of this refinement.
