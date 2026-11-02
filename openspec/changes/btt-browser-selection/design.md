## Context

`QuickActionRunner.selection(in:using:)` reads Accessibility, then borrows a ⌘C copy
(`QuickActionRunner.swift:19-27`). `ExtensionHostBridge.selectedText()` reads Accessibility, then
borrows a copy for user-initiated commands. Chrome answers neither Accessibility read, and the
copy fails while Secure Event Input is on.

Tinycast is not sandboxed and holds the Apple Events entitlement
(`Tinycast/Tinycast.entitlements:11`) and `NSAppleEventsUsageDescription` (`Info.plist:75`).

## Goals / Non-Goals

**Goals:**

- Read a browser selection without a keystroke and without touching the clipboard.
- Leave every other app on its current path.

**Non-Goals:**

- A Tinycast browser extension or native messaging host.
- Installing or configuring BetterTouchTool or its Chrome extension.
- Selections inside cross-origin iframes. Chrome's `execute javascript` runs in the top frame.

## Decisions

### 1. BetterTouchTool runs the JavaScript

Tinycast sends action 600 through `tell application id "com.hegenberg.BetterTouchTool" to
trigger_action`. The action targets the target app's bundle identifier, so the read works while
the palette holds focus. BetterTouchTool chooses between its extension and AppleScript.

### 2. The reader runs only when it can succeed

The reader returns `nil` at once when the target is not a supported browser or BetterTouchTool is
not running. It never launches BetterTouchTool.

### 3. A focused field comes first

The script returns the selected part of a focused `input` or `textarea`, because the page
selection does not include it. Otherwise it returns `window.getSelection()`.

### 4. Failure falls through

An AppleScript error, a 2 s timeout, a BTT error object or a blank result returns `nil`, and the
caller continues to the ⌘C borrow.

## Risks / Trade-offs

- **Dependency.** Without BetterTouchTool, browsers keep the current ⌘C path.
- **Permission prompt.** The first read asks to let Tinycast control BetterTouchTool. A denial
  makes every read return `nil`.
- **Chrome setting.** Without BTT's Chrome extension, Chrome needs "Allow JavaScript from Apple
  Events".
