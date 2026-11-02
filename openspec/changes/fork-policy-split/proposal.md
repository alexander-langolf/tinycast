## Why

A change to a trigger rule, such as "offer Fix on a Slack selection", requires a Tinycast rebuild
today. The rule lives in Swift (`ForkLyraText.selectionTriggerApps`, `selectionDelay`), as do
Lyra's word and length limits, delays, prompts and model routing.

Tinycast already depends on BetterTouchTool. BetterTouchTool has a "Text Selection Did Change"
trigger, app scoping through Conditional Activation Groups, hotkeys, variables and JavaScript.
Its configuration changes live, and `export_preset` writes it to a file. Sasha chose to split the
system three ways:

- BetterTouchTool owns when and where an action fires.
- Tinycast tools own what happens.
- Text files in the repository own the content and limits.

## What Changes

- Tinycast drops the compiled Slack selection rule.
- A `policy/` folder at the repository root holds `lyra.json` (limits, delays, mode list, model
  routing) and `prompts/*.txt`. Tinycast reloads it when a file changes. Tinycast validates every
  change and keeps the last valid version when a change fails.
- A new Automation tool, `lyra_offer`, shows Lyra's Fix marker for the current selection. Tab
  previews the fix and a second Tab applies it, as in typed Fix.
- Each Lyra decision records the policy version.
- A BetterTouchTool preset, `btt/tinycast.bttpreset`, holds the "Slack selection offers Fix"
  trigger. The preset calls `tinycast call lyra_offer`.

## Capabilities

### New Capabilities

- `fork-policy-split`: hot-reloaded policy files, the `lyra_offer` tool and the BetterTouchTool
  trigger preset.

### Modified Capabilities

None.

## Impact

- Fork files in `Tinycast/Fork/Core/Policy/` and `Tinycast/Fork/Lyra/`.
- The bundled prompts in `Tinycast/Resources/LyraPrompts` become the fallback copy.
- New `policy/` and `btt/` folders at the repository root.
