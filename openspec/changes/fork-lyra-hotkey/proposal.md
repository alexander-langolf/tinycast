## Why

Lyra's rewrite panel needs the same configurable hotkey controls as other built-in commands.
The default binding is Hyper+R, and the seed must preserve existing shortcuts and user choices.

## What Changes

- “Rewrite with Lyra” becomes a built-in palette command with the `sparkles` symbol.
- Settings under Commands and the settings-file mirror expose the command's binding.
- A fork-owned seed assigns Hyper+R once when Lyra is unbound and the chord is free.
- The seed uses the user's Include Shift setting and records every initial attempt.
- The rewrite command calls the existing gated `ForkLyraCoordinator.openPanel()` entry point.
- Lyra retains temporary card keys and removes the fixed panel shortcut.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `fork-local-lyra`: bindable rewrite command, one-time default, and normal shortcut conflict checks.

## Impact

- The launcher command catalog and coordinator receive tagged `local-lyra` hooks.
- `AppCore` invokes the fork-owned seed before `HotKeyManager.start()`.
- `Tinycast/Fork/Lyra/Service/ForkLyraHotKey.swift` owns seeding and persistent conflict detection.
- An isolated UserDefaults harness covers seeding, preserved choices, and occupied chords.
- The feature guides, fork hook table, and original Lyra change describe the configurable command.
