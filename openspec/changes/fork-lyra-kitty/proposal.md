## Why

Kitty exposes the prompt glyph through Accessibility and provides no useful caret bounds for Lyra.
The rewrite card needs the terminal selection and a pointer anchor.
Terminal delivery must preserve shell safety.

## What Changes

- A dedicated selection adapter reads kitty through remote control.
- The rewrite command uses a Copy-only card near the mouse pointer.
- Empty selections and failed reads produce a short HUD without a card.
- Fix on pause and Accessibility text reads exclude kitty.
- Lyra rejects writes into kitty.
- The service shares model streaming between Accessibility snapshots and plain text.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `fork-local-lyra`: kitty remote-control selection, Copy-only delivery, and pointer placement.

## Impact

- `Tinycast/Fork/Core/Adapters/ForkKittySelectionSource.swift` owns the remote-control read.
- `Tinycast/Fork/Lyra/` owns routing, streaming, Copy-only acceptance, and positioning.
- `Tests/fork-lyra-kitty-test.swift` defines the regression harness.
- `Scripts/run-tests.sh` registers the harness.
- `docs/features/lyra.md` and `docs/fork.md` describe the selection and delivery contract.
- XcodeGen registers added Swift sources in the generated project.
