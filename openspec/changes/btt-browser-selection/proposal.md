## Why

Quick Actions and an extension's `getSelectedText()` fail on a Google Chrome selection. Chrome
exposes no web selection to Accessibility, so Tinycast falls back to a ⌘C borrow. The borrow
refuses to run while Secure Event Input is on (`TextInjector.swift:171`), and a background app
can leave Secure Input on.

BetterTouchTool's action 600, "Run JavaScript in Browser", evaluates JavaScript in a browser's
active tab and returns the result through AppleScript `trigger_action`. A test on 2026-10-28
returned a Chrome selection with no keystroke and no clipboard change. BTT uses its Chrome
extension when that extension is connected, and otherwise uses Chrome's AppleScript
`execute javascript`.

## What Changes

- A fork reader, `ForkBTTBrowserSelection`, asks BetterTouchTool for the selection when the
  target app is a supported browser and BetterTouchTool is running.
- Quick Actions use the reader after an empty Accessibility read and before the ⌘C borrow.
- An extension's `getSelectedText()` uses the reader after an empty Accessibility read and before
  the selection borrow.

## Capabilities

### New Capabilities

- `btt-browser-selection`: reading a browser selection through BetterTouchTool.

### Modified Capabilities

None.

## Impact

- New file `Tinycast/Fork/Selection/ForkBTTBrowserSelection.swift`.
- `// FORK: btt-selection` hooks in `QuickActionRunner.swift` and `ExtensionHostBridge.swift`,
  listed in `docs/fork.md`.
- The first read shows the macOS prompt that lets Tinycast control BetterTouchTool.
