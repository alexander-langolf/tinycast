## Why

The launcher disappears completely between uses. A persistent, half-scale field at the top of the
screen gives Tinycast a visible resting place, with a continuous movement into the working position
when summoned, matching the supplied Droppy placement reference and launcher sketch.

## What Changes

- Show the main launcher field at 0.5 visual scale, centred at the top safe edge while inactive.
- Invoke through the existing hotkey, animating translation and uniform scale to the existing active
  palette position and normal size; show only one perceived field throughout the transition.
- Return the field to its resting position when the interactive palette is dismissed.
- Keep the resting field passive: no keyboard focus, retained query disclosure, results or feature work.
- Preserve active placement, theme, interface size, search and feature-mode behavior; support reduced
  motion, multiple displays, Spaces and interrupted transitions.
- Clicking the resting field also invokes the launcher, as confirmed by the user.

## Capabilities

### New Capabilities

- None; persistent launcher presentation belongs to the existing UI area.

### Modified Capabilities

- `ui`: Add the persistent resting field and invocation/dismissal transition contracts, including
  logical activity, placement and accessibility behavior.

## Impact

- PaletteCoordinator and PaletteWindowController show/hide, focus, placement and lifecycle handling.
- Fork-owned palette presentation/motion, launcher-field rendering and AppCore wiring.
- Existing palette visibility consumers, hotkeys, outside-click dismissal, mode restoration and
  display/Space changes require regression checks.
- New deterministic presentation/geometry tests and targeted rendered acceptance; no new dependency,
  external service, permissions or user-facing preference is proposed.
- This change produces proposal artifacts only. Application code remains unchanged until implementation.
