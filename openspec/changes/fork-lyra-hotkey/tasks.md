> Codex implements groups 1–3 without tests, builds, typechecking, lint, or app launch.
> Claude owns group 4.

## 1. Built-in command

- [x] 1.1 Add `lyraRewrite` with the title “Rewrite with Lyra” and the `sparkles` symbol.
- [x] 1.2 Include the command in the palette, Commands settings, and `commands.builtIn` records through the existing catalog.
- [x] 1.3 Route palette and hotkey invocation to `ForkLyraCoordinator.openPanel()` with the existing enable and policy gates.
- [x] 1.4 Remove the fixed panel shortcut and preserve temporary marker and card keys.

## 2. One-time default

- [x] 2.1 Add the fork-owned Hyper+R seed using the user's Include Shift setting.
- [x] 2.2 Preserve stored Lyra bindings, refuse occupied chords, and record the first attempt.
- [x] 2.3 Call the seed before hotkey loading through a tagged startup hook.
- [x] 2.4 Add an isolated seeding harness and register the shipped source dependencies in the runner.

## 3. Documentation

- [x] 3.1 Document the command, storage keys, settings-file record, seed-attempt rule, and disabled behavior.
- [x] 3.2 Register every new upstream hook in `docs/fork.md`.
- [x] 3.3 Replace the matching fixed-hotkey wording in `fork-local-lyra`.

## 4. Verification (Claude)

- [ ] 4.1 Run the new hotkey harness and the existing Lyra and observability harnesses.
- [ ] 4.2 Build Debug with no new warnings.
- [ ] 4.3 Run `openspec validate fork-lyra-hotkey --strict` and `openspec validate fork-local-lyra --strict`.
- [ ] 4.4 Run `Scripts/fork-audit.sh`; retain the known unrelated undocumented hooks.
- [ ] 4.5 Synchronize the localized command title and translate the eight non-English languages.
- [ ] 4.6 Relaunch Dev and inspect `hotkey.command:lyra-rewrite` and `fork.lyra.panelHotKeySeeded` in `com.tinycast.app.dev`.
- [ ] 4.7 Check Hyper+R, rebinding, unbinding across relaunch, occupied chords, and Include Shift variants.
- [ ] 4.8 Check palette invocation, disabled Lyra, policy gates, and temporary marker and card keys.
