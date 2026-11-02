## Why

Tinycast's capabilities are reachable only through its own palette and hotkeys. Script Kit, or
any other front end, cannot read a selection or run a Quick Action without Tinycast's UI. The
selection logic has three inline paths in `QuickActionRunner.selection` and
`ExtensionHostBridge.selectedText`: Accessibility, BetterTouchTool and a ⌘C borrow. The Quick
Action flow lives in `QuickActionCoordinator`, which reads palette state and hides the palette.

The Automation API (`Tinycast/Features/Automation/`) already serves a local HTTP/MCP endpoint with
scopes, approvals and an audit log. It exposes 10 operations, none of them a capability.

## What Changes

- Fork-owned ports in `Tinycast/Fork/Core/Ports/`: `ForkSelectionSource` and `ForkTextSink`.
- Adapters in `Tinycast/Fork/Core/Adapters/`: Accessibility, BetterTouchTool browser and
  clipboard-borrow selection sources, and a `TextInjector` text sink.
- `ForkSelectionReader` runs the sources in order. `QuickActionRunner` and `ExtensionHostBridge`
  call the reader in place of their inline paths.
- `ForkQuickActionService` runs a Quick Action without UI: it reads the selection, runs the model
  and optionally replaces the selection.
- New Automation tools: `selection_read` and `quick_action_run`, under a new `selection` scope.
- Every Automation call records a `ForkTrace` with its client, operation, duration and outcome.
- The `tinycast` CLI gains `call <tool> [--args <json>]`, so a script can run any tool.
- A Script Kit script in `Scripts/scriptkit/` runs Rewrite through the CLI.

## Capabilities

### New Capabilities

- `fork-core-capabilities`: ports, adapters and headless capability operations.

### Modified Capabilities

None.

## Impact

- New fork files under `Tinycast/Fork/Core/`.
- Tagged hooks in `QuickActionRunner.swift`, `ExtensionHostBridge.swift`,
  `AutomationScope.swift`, `AutomationOperationCatalog.swift`, `AutomationRunner.swift`,
  `AutomationRouter.swift` and `TinycastCLI/main.swift`, listed in `docs/fork.md`.
