## Context

Tinycast is a fork that merges `upstream/main`. Fork code lives in `Tinycast/Fork/`, and every
edit to an upstream file carries a `// FORK: <tag>` comment listed in `docs/fork.md`
(`Scripts/fork-audit.sh` checks the list).

`AutomationAuditLog` (`Tinycast/Features/Automation/Service/AutomationAuditLog.swift`) writes a
rotating JSONL file with `0600` permissions: 5 MB per file, 3 files kept. The Automation server
exposes resources from `AutomationOperationCatalog` and answers them in `AutomationRunner`
(`AutomationRunner.swift:105` for `tinycast://context`). `TinycastCLI/main.swift` accepts only
`mcp --stdio`.

This change is the first slice of a larger direction. Capabilities move behind fork-owned ports
in `Tinycast/Fork/Core/`, and other front ends (Script Kit) call them through the Automation API.
Upstream files stay in place.

## Goals / Non-Goals

**Goals:**

- One query answers "what happened in this Rewrite": every step, its duration and its outcome.
- BetterTouchTool is running whenever Tinycast needs it.
- The CLI reads health and logs without the palette.

**Non-Goals:**

- An in-app log viewer.
- Metrics export or remote telemetry.
- Supervising apps other than BetterTouchTool. The supervisor takes a descriptor, so llama-server
  joins in the Local Lyra slice.

## Decisions

### 1. Events, not free text

`ForkLog` records `ForkEvent` values with these fields: time, level, category, operation,
correlation ID, step, duration in milliseconds, outcome and a small string map. Each event goes to
an `os.Logger` with subsystem `com.tinycast` and the event's category, and to the JSONL mirror.

### 2. Correlation through a task-local value

`ForkTrace.run(_ operation:category:_ body:)` creates a correlation ID, stores it in a
`@TaskLocal`, records `start`, then records `end` with the duration and outcome, or `error` with
the error description. Nested `ForkTrace.step` calls inherit the ID. An automation call records
its client ID as a field.

### 3. Content never reaches the log

Events record lengths, counts, bundle identifiers and error codes. They never record selected
text, prompts, model output, clipboard contents, tokens or the Authorization header. `ForkLog`
offers no API that takes free-form user content.

### 4. The JSONL mirror reuses the audit log's rules

The mirror writes `Application Support/<app>/Diagnostics/events.jsonl` with `0600` permissions,
rotates at 5 MB and keeps 3 files, as `AutomationAuditLog` does. A write failure falls back to the
unified log only. Writes run off the main actor.

### 5. A supervisor per companion app

`ForkAppSupervisor` takes a `ForkSupervisedApp` descriptor: bundle identifier, display name, a
readiness probe and a relaunch policy. Process and workspace access goes through a
`ForkAppControl` protocol, so the harness can supply a fake. The production adapter wraps
`NSWorkspace` and `NSRunningApplication`.

- At Tinycast launch, the supervisor launches BetterTouchTool when it is not running.
- On `NSWorkspace.didTerminateApplicationNotification` for BetterTouchTool, it relaunches the app
  after 2 s.
- `ensureReady(timeout:)` runs before each BetterTouchTool call. It launches BetterTouchTool when
  needed and waits for the probe, up to 3 s.
- The BetterTouchTool probe sends `get_string_variable "tinycast_probe"`, an undefined variable, through
  AppleScript with a 1 s timeout. Any reply counts as ready.
- Relaunches are capped at 3 in 10 minutes. After the cap, the supervisor reports `gaveUp` and
  stops relaunching until the next Tinycast launch or a manual `tinycast health --repair`.

`ForkBTTBrowserSelection.read` calls `ensureReady` in place of its running check.

### 6. Health is an Automation resource

`tinycast://health` returns JSON with these entries:

- each supervised app: state (`running`, `launching`, `notRunning`, `gaveUp`), last launch time
  and relaunch count;
- Secure Event Input: on or off, with the owning process identifier when `ioreg` reports one;
- the Accessibility permission.

The resource needs the `contextRead` scope.

### 7. The CLI reads logs from the file

`tinycast logs` reads the JSONL mirror directly, so it works while Tinycast is not running. It
takes `--channel`, `--follow`, `--id <correlation>`, `--op <operation>`, `--level` and
`--since <minutes>`. It prints one line per event.

`tinycast health` reads `tinycast://health` through the existing bridge and prints a table.
`--json` prints the raw JSON.

### 8. Debug traces move

The DEBUG-only `selectionTrace` in `TextInjector.swift` and `QuickActionRunner.swift` and the
`trace` in `ForkClaudeAccountProvider.swift` become `ForkLog` events. The request-header line
keeps its exclusion of the Authorization header.

## Risks / Trade-offs

- **Unwanted relaunch.** A user who quits BetterTouchTool on purpose gets it back. The cap of 3
  in 10 minutes bounds the loop.
- **Log volume.** Each Quick Action writes about 6 events, which is well inside 5 MB per file.
- **Upstream merges.** The hooks are one or two lines each, and the logic stays in fork files.
