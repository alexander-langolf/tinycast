## Context

`AccessibilityText.read` asks the focused element for `AXSelectedText`, then for the web
selection's text-marker range (`Tinycast/Platform/AccessibilityText.swift:37-82`). Before either
read, it sets `AXManualAccessibility` on the application (`:56`).

A probe against Google Chrome on 2026-10-28 measured these results:

| Request | Result |
| --- | --- |
| `AXManualAccessibility` in Chrome's attribute names | absent |
| Set `AXManualAccessibility` | `-25205` (attribute unsupported) |
| `AXEnhancedUserInterface` in Chrome's attribute names | present |
| Set `AXEnhancedUserInterface` | `-25208` (not implemented) |
| `AXWebArea` under the main window, before and 1.5 s after the set | not found |

`TextInjector.copySelection(from:)` (`TextInjector.swift:225-262`) does the following:

1. It drains pending deliveries and activates the target.
2. It snapshots the pasteboard and pauses clipboard-history capture.
3. It posts ⌘C to the target and polls the change count for up to 1 s.
4. It restores the snapshot and resumes capture.

Quick Actions call it after an empty Accessibility read (`QuickActionRunner.swift:19-22`).
Quicklinks hide a visible palette first, because the palette holds key and a ⌘C would land in its
search field (`QuicklinkCoordinator.swift:185-187`).

`ExtensionHostBridge.selectedText()` (`ExtensionHostBridge.swift:577-590`) reads Accessibility
only, through `context.pasteTarget`. The bridge's `system(method:arguments:)` is already `async`.

## Goals / Non-Goals

**Goals:**

- `getSelectedText()` returns the Chrome selection for a user-initiated command.
- The user's clipboard and clipboard history end unchanged.
- A command that shows a view keeps its palette on screen after the read.

**Non-Goals:**

- Enabling Chrome's accessibility tree. `AXEnhancedUserInterface` takes effect late in Chromium and
  disturbs window moves, so Tinycast does not set it.
- Reading the selection through Chrome DevTools (cdp-mux).
- Changing automatic snippet expansion, Quick Actions, Quicklinks or the Snippets command.
- Menu-bar commands. `ExtensionMenuBarHost` has no injector and keeps the Accessibility-only read.

## Decisions

### 1. The context performs the borrow

`ExtensionHostContext` gains `func borrowSelection(from app: NSRunningApplication) async -> String?`.
A protocol extension returns `nil`, so `ExtensionMenuBarHost` and the harness stubs need no change.
`ExtensionManager` forwards the call to `ExtensionCoordinator`. The bridge stays free of window and
injector dependencies, as its protocol comment requires.

### 2. The bridge falls back only for user-initiated runs

`selectedText()` becomes `async`. It reads Accessibility first. When that read returns no text and
`context.activeLaunchType` is `.userInitiated`, the bridge awaits `context.borrowSelection(from:)`.
An empty or `nil` result throws the existing `getSelectedText (no selection)` error.

### 3. The coordinator hides and restores the palette

`ExtensionCoordinator.borrowSelection(from:hasRunningCommand:)` does the following:

1. It records whether the palette is visible.
2. If the palette is visible, it hides the palette with `restoreFocus: false`.
3. It awaits `injector.copySelection(from:)`.
4. If the palette was visible, it shows the palette again with `reopenPalette(hasRunningCommand:)`,
   which picks extension-command mode while a command is running.

The palette is reopened in every case, including a failed copy.

Hiding the palette schedules a pop to root, and the default timeout runs it at once
(`PaletteWindowController.swift:177-193`, `AppSettings.swift:734`). Leaving extension-command mode
stops the running command (`RootPaletteView.swift:543`). The bridge therefore sets
`isBorrowingSelection` for the length of the borrow. `ExtensionManager.isHoldingCommand` reports
either a sign-in or a borrow. The palette's pop to root and `consumePreservedState` honour it, as
they already honour `isSigningIn` for an OAuth sign-in. `AppCore` needs no change, because the
coordinator reaches the injector through `core.textInjector`.

### 4. The comment states the measured fact

The comment above `activateManualAccessibility` says that Electron builds its tree only once asked,
and that Chrome does not support the attribute.

## Risks / Trade-offs

- **Palette flicker.** A view command whose Accessibility read fails hides and shows the palette
  once. This runs only after an empty Accessibility read.
- **Copy side effects.** A target app can react to ⌘C, for example with a copy toast in a web page.
  Quick Actions accept the same effect.
- **Timing.** The borrow waits up to 1 s for the copy, as Quick Actions do.
