## Why

Lyra's floating suggestion panel needs the variant C layout selected from the SwiftUI prototype.
The card presents the captured original text and the replacement with visible, clickable actions.

## What Changes

- The Fix marker uses a compact capsule with sparkles, Fix, and a Tab keycap.
- The preview and rewrite cards show struck-through original text and an arrow beside the replacement, with a plain copy icon at the end of that row.
- The cards carry no mode tag and no Accept or Dismiss buttons; Tab, Return and Escape apply and dismiss.
- The cards follow the system light or dark appearance, independent of Tinycast's colour theme.
- The rewrite card shows no mode controls; keys 1–3 and arrows switch mode.
- The rewrite card shows a progress indicator and "Reading your text…" before the first partial response.
- The card uses the existing system material and fits its content within bounded text areas.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `fork-local-lyra`: variant C presentation, clickable actions, and explicit loading and response states.

## Impact

- `Tinycast/Fork/Lyra/UI/ForkLyraSuggestionController.swift` owns the AppKit layout and controls.
- `Tinycast/Fork/Lyra/UI/ForkLyraCoordinator.swift` passes original text and response state to the controller.
- The existing coordinator owns keyboard registration, cancellation, validation, insertion, and dismissal.
- Issue paging, issue categories, and reasons require a separate Harper change.
