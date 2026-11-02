## Why

Tinycast runs code that talks to other apps: BetterTouchTool, Chrome, Accessibility, the
clipboard, model providers and terminals. A failure in that code leaves no record. Only 13 files
log through `os.Logger`, and the selection, Quick Action and BetterTouchTool paths log nothing in
Release builds. A user who sees "Google Chrome doesn't share its text with Tinycast" has no way to
learn which step failed.

The Chrome selection path depends on BetterTouchTool (`btt-browser-selection`). When
BetterTouchTool is not running, the path falls through to a ⌘C borrow, which Secure Input blocks.

## What Changes

- A fork-owned observability layer records each operation as structured events: a correlation
  ID, the operation name, each step, its duration and its outcome. Events go to the unified log
  under subsystem `com.tinycast` and to a rotating JSONL file in Application Support.
- The selection read, Quick Actions and BetterTouchTool calls report through that layer.
- A fork-owned app supervisor keeps BetterTouchTool running. It checks at launch and before each
  BetterTouchTool call, and it relaunches BetterTouchTool after the app terminates.
- The Automation API gains a `tinycast://health` resource. The `tinycast` CLI gains `health` and
  `logs` subcommands.
- The DEBUG-only `SelectionCopy` and `ClaudeAccount` traces move onto the new layer.

## Capabilities

### New Capabilities

- `fork-observability`: structured operation events, their storage, and the CLI that reads them.
- `fork-app-supervision`: keeping a required companion app running and reporting its health.

### Modified Capabilities

None.

## Impact

- New fork files under `Tinycast/Fork/Core/Observability/` and `Tinycast/Fork/Core/Supervision/`.
- Tagged hooks in `AppCore.swift`, `AutomationOperationCatalog.swift`, `AutomationRunner.swift`,
  `TinycastCLI/main.swift`, `QuickActionRunner.swift`, `TextInjector.swift` and
  `ExtensionHostBridge.swift`, listed in `docs/fork.md`.
- New harnesses registered in `Scripts/run-tests.sh`.
