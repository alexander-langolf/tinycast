## Why

Writing assistance should appear when explicitly requested.
Inline autocomplete owns the typing surface until the user opens Lyra.

## What Changes

- Typing and selection changes schedule no Fix request and show no Lyra marker or suggestion.
- The typed-Fix setting is removed from preferences, UI, and settings-file schema.
- The Lyra command, default Hyper+R, starts Fix on the selection or the entire focused field.
- The card accepts a completed result with Tab or Enter and dismisses with Escape.
- Fix is the first mode; Refine, Professional, and Friendly remain available inside the card.
- The existing kitty selection path retains Copy-only delivery and starts in Fix.
- Workflow-server markers retain their explicit preview and application flow.

## Capabilities

### New Capabilities

- `fork-lyra-hotkey-only`: explicit Fix cards, whole-field fallback, and card keyboard ownership.

### Modified Capabilities

None.
The active `fork-local-lyra` change marks its superseded interaction requirements directly.

## Impact

Changes stay within the fork-owned Lyra coordinator, card controller, settings, and runtime mode projection.
Existing tagged settings hooks remove the typed-Fix schema binding.
The localization catalog and fork documentation describe the card controls.
Terminal autocomplete, terminal acceptance, and terminal learning remain outside phase 1.
