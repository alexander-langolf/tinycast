> Tests in group 4 come after Sasha's Dev check in group 3.

## 1. Reader

- [x] 1.1 Add `Tinycast/Fork/Selection/ForkBTTBrowserSelection.swift` (design §1–§4).

## 2. Hooks and docs

- [x] 2.1 `QuickActionRunner.swift`: read through BetterTouchTool after an empty Accessibility
  read and before the ⌘C borrow (`// FORK: btt-selection`).
- [x] 2.2 `ExtensionHostBridge.swift`: read through BetterTouchTool before the selection borrow
  (`// FORK: btt-selection`).
- [x] 2.3 `docs/fork.md`: list both hooks.

## 3. Dev check (Sasha)

- [ ] 3.1 With Secure Input on, select text in Chrome and run Rewrite. Confirm the rewrite uses
  the selection.
- [ ] 3.2 Confirm the clipboard and clipboard history are unchanged.
- [ ] 3.3 Select text in a Chrome text field and run Rewrite. Confirm the field's selection
  arrives.

## 4. Harness

- [ ] 4.1 Cover the AppleScript escaping and the unsupported-browser skip in a harness.
