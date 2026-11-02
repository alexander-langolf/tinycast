## Why

An extension's `getSelectedText()` returns nothing in Google Chrome. Tinycast reads the selection
only through Accessibility, and Chrome exposes no web selection to it. `AccessibilityText` enables
Chromium's tree with `AXManualAccessibility`. Chrome does not list that attribute and refuses it
with `-25205` (attribute unsupported), measured on 2026-10-28. The attribute is Electron's switch
([Electron accessibility](https://www.electronjs.org/docs/latest/tutorial/accessibility)).

Raycast 2.9.0 and BetterTouchTool 6.958 both fall back to a simulated ⌘C with a clipboard snapshot
and restore when Accessibility returns nothing. Both binaries carry the strings for that path:
Raycast's "Selected text retrieved through Clipboard" and BetterTouchTool's
`axSelectedTextWithClipboardFallback`. Tinycast already has the same borrow,
`TextInjector.copySelection`, and Quick Actions, Quicklinks and the Snippets command use it.
Extensions do not.

## What Changes

- `getSelectedText()` keeps its Accessibility read. When that read returns nothing for a
  user-initiated command, Tinycast borrows a ⌘C copy through `TextInjector.copySelection`, as Quick
  Actions do.
- While the palette is on screen, the borrow hides the palette, copies, and shows the palette
  again in its extension-command mode.
- Background launches and menu-bar commands keep the Accessibility-only read.
- The comment on `AccessibilityText.activateManualAccessibility` names Electron only.
- Automatic snippet expansion keeps its Accessibility-only read. A ⌘C there would land between
  keystrokes.

## Capabilities

### New Capabilities

- `extension-selection`: how an extension's `getSelectedText()` reads the selection, including
  the clipboard fallback and its limits.

### Modified Capabilities

None.

## Impact

- `// FORK: selection-copy` hooks in `ExtensionHostBridge.swift`, `ExtensionManager.swift`,
  `ExtensionCoordinator.swift`, `AppCore.swift` and `AccessibilityText.swift`.
- `docs/fork.md` lists the hooks; `docs/features/extensions.md` describes the fallback.
