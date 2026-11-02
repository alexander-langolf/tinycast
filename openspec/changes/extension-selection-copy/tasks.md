> Run `./Scripts/run-tests.sh` and `Scripts/fork-audit.sh` after group 2. Tests in group 4 come
> after Sasha's Dev check in group 3.

## 1. Context hook

- [x] 1.1 `ExtensionHostBridge.swift`: add `borrowSelection(from:) async -> String?` to
  `ExtensionHostContext`, with a protocol-extension default that returns `nil` (design §1,
  `// FORK: selection-copy`).
- [x] 1.2 `ExtensionManager.swift`: forward `borrowSelection(from:)` to the coordinator
  (`// FORK: selection-copy`).
- [x] 1.3 `ExtensionCoordinator.swift`: implement the hide, copy and reopen sequence through
  `core.textInjector`. `PaletteWindowController.swift`: honour `isHoldingCommand` in the pop to
  root (design §3, `// FORK: selection-copy`).

## 2. Bridge and docs

- [x] 2.1 `ExtensionHostBridge.swift`: make `selectedText()` async, and fall back to
  `borrowSelection(from:)` for user-initiated runs when Accessibility returns no text (design §2).
- [x] 2.2 `AccessibilityText.swift`: correct the comment above `activateManualAccessibility`
  (design §4, `// FORK: selection-copy`).
- [x] 2.3 `docs/fork.md`: list every new hook. `docs/features/extensions.md`: describe the
  fallback beside `getSelectedText`.

## 3. Dev check (Sasha)

- [ ] 3.1 Select text in Chrome, run an extension command that reads the selection, and confirm the
  text arrives.
- [ ] 3.2 Confirm that the clipboard holds its previous value and that clipboard history gained no
  entry.
- [ ] 3.3 Run a view command the same way, and confirm the palette comes back showing the command.

## 4. Harness

- [ ] 4.1 Cover the fallback order, the background-launch skip and the default `nil` borrow with a
  stub context in the extensions harness.
