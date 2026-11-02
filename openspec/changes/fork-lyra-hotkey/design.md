## Context

`HotKeyAction.command(CommandID)` makes built-in commands bindable through the catalog.
`HotKeyManager` loads JSON bindings from each action's `defaultsKey`.
The launcher settings-file adapter derives command records from the same catalog.
`ForkLyraCoordinator.openPanel()` owns Lyra's enable and policy gates.

## Goals / Non-Goals

**Goals:**

- Expose “Rewrite with Lyra” in the palette, Settings, and the settings-file mirror.
- Seed Hyper+R once without replacing another action's binding or a user's Lyra binding.
- Preserve temporary card keys and the existing rewrite behavior.

**Non-Goals:**

- A general default-hotkey mechanism for upstream commands.
- New modes, policy rules, panel layouts, logging, or text insertion behavior.
- Changes to other pending work in the checkout.

## Decisions

### 1. The command belongs in the palette and Commands settings

`CommandID.lyraRewrite` has the stable raw value `command:lyra-rewrite`.
The title is “Rewrite with Lyra”, and the symbol is `sparkles`.
The command has no feature-pane owner, following the catalog's default Commands ownership.
The settings file uses `commands.builtIn` with the record name `lyra-rewrite`.
The normal command action participates in recording, conflicts, persistence, and dispatch.

### 2. Fork-owned seeding precedes the normal load

`AppCore` calls `ForkLyraHotKey.seed` before `HotKeyManager.start()`.
The call supplies the action's computed defaults key and `settings.hyperKeyIncludesShift`.
The seed constructs R with `KeyShortcut.hyperChord(includesShift:)` and the existing Carbon conversion.
The manager loads and registers the result through its normal binding path.

The seed checks `fork.lyra.panelHotKeySeeded` before writing.
The first attempt records the flag even when a stored Lyra binding or an occupied chord prevents seeding.
Any stored value at the Lyra action's key remains untouched.
The seed decodes stored `hotkey.` values with the real `HotKeyBinding` format and checks `conflicts(with:)`.
The scan includes actions outside the current installed-item indexes, preserving their stored chord ownership.
An unbound action receives Hyper+R only when no decoded binding conflicts.
The flag prevents later unbinding, rebinding, or release of an occupied chord from triggering another seed.
The flag and binding use the app channel's UserDefaults domain.

### 3. Both invocation routes use the existing panel gate

The launcher restores the previous app's focus when the palette is visible, then calls `openPanel()`.
Disabled Lyra ignores the command before changing palette visibility.
`openPanel()` retains the policy, focused-field, and in-flight operation checks.
The fixed `fork.lyra.panel` registration is removed.
The marker and card retain their temporary Tab, Escape, Return, number, and arrow registrations.

## Risks / Trade-offs

- A skipped seed remains skipped across launches; the user can assign a free shortcut in Settings.
- A stored shortcut in another running app can prevent Carbon registration outside Tinycast's conflict checks.
- Native palette focus restoration and hotkey delivery require a Dev app check.
- The localized command title uses the existing resource API; catalog synchronization belongs to Claude's verification pass.

## Verification

Claude owns the Debug build, harness execution, strict OpenSpec validation, fork audit, and Dev checks.
The worker performs implementation and source review without tests, builds, typechecking, lint, or app launch.
The seed harness uses isolated `UserDefaults(suiteName:)` stores and the shipped shortcut and binding types.
