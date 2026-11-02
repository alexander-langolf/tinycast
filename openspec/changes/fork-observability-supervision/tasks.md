> Codex implements groups 1–4. Claude builds, runs the harnesses and relaunches Dev. Group 5 is
> Sasha's Dev check.

## 1. Observability

- [x] 1.1 Add `ForkEvent`, `ForkLog` and the JSONL mirror in `Tinycast/Fork/Core/Observability/`
  (design §1, §3, §4).
- [x] 1.2 Add `ForkTrace` with the task-local correlation ID (design §2).

## 2. Supervision

- [x] 2.1 Add `ForkAppControl`, its `NSWorkspace` adapter, `ForkSupervisedApp` and
  `ForkAppSupervisor` in `Tinycast/Fork/Core/Supervision/` (design §5).
- [x] 2.2 Add the BetterTouchTool descriptor and its probe. Start the supervisor from `AppCore`
  (`// FORK: app-supervision`).
- [x] 2.3 `ForkBTTBrowserSelection.read`: call `ensureReady` in place of the running check.

## 3. Instrumentation

- [x] 3.1 Trace the Quick Action selection read and run (`QuickActionRunner.swift`), the extension
  `getSelectedText` read (`ExtensionHostBridge.swift`) and `TextInjector.copySelection`
  (`// FORK: observability`).
- [x] 3.2 Replace the DEBUG `selectionTrace` and the `ForkClaudeAccountProvider` trace with
  `ForkLog` events (design §8).

## 4. Health and CLI

- [x] 4.1 Add `tinycast://health` to `AutomationOperationCatalog` and answer it in
  `AutomationRunner` (design §6, `// FORK: app-supervision`).
- [x] 4.2 Add `tinycast health` and `tinycast logs` to `TinycastCLI/main.swift` (design §7,
  `// FORK: observability`).
- [x] 4.3 List every hook in `docs/fork.md`.
- [x] 4.4 Add harnesses for event encoding, the content rule, rotation, correlation inheritance,
  the relaunch policy with a fake `ForkAppControl`, the BetterTouchTool AppleScript escaping and
  the unsupported-browser skip. Register them in `Scripts/run-tests.sh`.

## 5. Dev check (Sasha)

- [ ] 5.1 Quit BetterTouchTool and confirm that it comes back within a few seconds.
- [ ] 5.2 Run Rewrite in Chrome, then `tinycast logs --op quickAction` and confirm one
  correlation ID covers every step.
- [ ] 5.3 Run `tinycast health` and confirm the output.
