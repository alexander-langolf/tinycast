> Codex implements groups 1–4. Claude builds, runs the harnesses and relaunches Dev. Group 5 is
> Sasha's Dev check.

## 1. Ports and adapters

- [x] 1.1 Add `ForkSelectionSource` and `ForkTextSink` in `Tinycast/Fork/Core/Ports/` (design §1).
- [x] 1.2 Add the Accessibility, BetterTouchTool and clipboard-borrow sources and the
  `TextInjector` sink in `Tinycast/Fork/Core/Adapters/` (design §1).
- [x] 1.3 Add `ForkSelectionReader` (design §2).

## 2. Callers

- [x] 2.1 `QuickActionRunner.selection` and `ExtensionHostBridge.selectedText`: call the reader
  in place of the inline paths, keeping current behaviour (`// FORK: core-capabilities`).
- [x] 2.2 Add `ForkQuickActionService` (design §3).

## 3. Automation and CLI

- [x] 3.1 Add the `selection` scope, `selection_read` and `quick_action_run` (design §4).
- [x] 3.2 Trace every call in `AutomationRouter` (design §5).
- [x] 3.3 Add `tinycast call` (design §6) and `Scripts/scriptkit/tinycast-rewrite.ts`.
- [x] 3.4 List every hook in `docs/fork.md`.

## 4. Harnesses

- [x] 4.1 Cover reader order, the borrow exclusion and trace steps with fake sources.
- [x] 4.2 Cover `quick_action_run` argument validation and the `tinycast call` argument parsing.

## 5. Dev check (Sasha)

- [ ] 5.1 Grant a client the `selection` scope, select text in Chrome and run the Script Kit
  script. Confirm the selection is rewritten.
- [ ] 5.2 Run Rewrite from the palette and confirm it behaves as before.
