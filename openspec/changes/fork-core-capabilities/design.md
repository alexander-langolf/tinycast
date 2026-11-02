## Context

`fork-observability-supervision` added `Tinycast/Fork/Core/Observability/` and
`Tinycast/Fork/Core/Supervision/`. Upstream files stay in place, and each upstream edit is a
small hook tagged `// FORK: <tag>` and listed in `docs/fork.md`.

`AutomationRunner` holds `unowned core: AppCore` (`AutomationRunner.swift:12`), so an operation
can reach `core.textInjector` and the AI settings. `AutomationRouter` dispatches every call.
`AutomationScope` lists the scopes, and the Automation settings show each scope's title.

## Goals / Non-Goals

**Goals:**

- A front end other than the palette reads the selection and runs a Quick Action.
- One selection path serves Quick Actions, extensions and Automation.

**Non-Goals:**

- Ports for window management, clipboard history, snippets, system actions or file search.
  Later slices add them on the same pattern.
- Moving `QuickActionCoordinator` logic out of the coordinator. The coordinator keeps its palette
  and HUD behaviour and calls the same runner.

## Decisions

### 1. Ports are protocols with one job

`ForkSelectionSource` has `kind` and `read(from: NSRunningApplication) async -> ForkSelection?`.
`ForkTextSink` has `replaceSelection(in:with:) async -> Bool`. Adapters wrap the existing code:
`AccessibilityText` (through `ForkSelectionDiagnostics`), `ForkBTTBrowserSelection` and
`TextInjector.copySelection` / `replaceSelection`. No adapter duplicates their logic.

### 2. The reader keeps today's order

`ForkSelectionReader` tries Accessibility, then BetterTouchTool, then the clipboard borrow. It
returns the text and the source kind, and it records one `ForkTrace` step per source. A caller
can exclude the borrow: extensions keep their background-launch rule, and the borrow needs the
palette hidden, which only `ExtensionCoordinator` can do.

### 3. Quick Actions run headless through a service

`ForkQuickActionService.run(action:target:apply:)` resolves the target as the frontmost app
outside Tinycast. It reads the selection through the reader, builds the provider the way
`QuickActionCoordinator` does, calls `QuickActionRunner.run`, and replaces the selection through
the sink when `apply` is true. It returns the output text, the selection source and whether the
replacement landed.

### 4. Selection access is its own scope

A new scope, `selection` ("Read and replace selected text"), guards both tools. `selection_read`
returns `{text, source, bundleID}`. `quick_action_run` takes `action` (one of `QuickAction`'s raw
values), an optional `instruction` and an optional `apply`, and returns `{text, source, applied}`.
Both are privileged and therefore audited.

### 5. Every call is traced at the router

`AutomationRouter` wraps each dispatch in `ForkTrace.run`. The trace records the client ID, the
operation name, the duration and the outcome. The trace records no arguments and no results.

### 6. The CLI calls any tool

`tinycast call <tool> [--args <json>] [--channel …]` sends `tools/call` through the existing
bridge and prints the result JSON. A Script Kit script runs
`tinycast call quick_action_run --args '{"action":"rewrite","apply":true}'`.

## Risks / Trade-offs

- **Content crosses the API.** `selection_read` hands selected text to a client. The scope is
  opt-in for each client and every call is audited.
- **Hook churn.** The reader replaces the inline paths in two upstream files, so those hooks
  grow by a few lines.
