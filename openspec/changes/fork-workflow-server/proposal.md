## Why

Rewrite runs as Swift inside `QuickActionCoordinator`. The coordinator reads palette state, holds
compiled prompts, picks the provider, streams, shows the HUD or panel, and replaces the
selection. Lyra follows the same shape. Changing a workflow step, prompt or condition requires a
Tinycast rebuild, and only Tinycast can run the workflow.

Sasha requires workflows such as Rewrite to be runnable actions on a server, detached from the
app. Tinycast keeps the native primitives.

## What Changes

- A Bun server in `server/` at the repository root runs workflow actions written in TypeScript.
  It reloads actions and prompts when their files change.
- Tinycast exposes the native primitives that workflows call through the Automation API:
  - `selection_read` returns a target handle;
  - `model_complete`, `text_replace`, `ui_preview` and `ui_marker` are new;
  - `hud_show` exists.
- Tinycast supervises the server, passes it credentials at launch, and reports it in
  `tinycast://health`.
- Callers run an action with `POST /actions/<name>`. Tinycast forwards
  `tinycast://run/<name>` links to the server for actions marked link-safe. BetterTouchTool uses
  that link with an Open URL action, without starting a process.
- Rewrite and Fix Grammar become server actions, and the Tinycast hotkeys and palette commands
  call them. Lyra's selection Fix becomes the server action `lyra-fix-selection`.
- `policy/` from `fork-policy-split` moves to `server/policy/` and `server/prompts/`.

## Capabilities

### New Capabilities

- `fork-workflow-server`: the workflow server, the native primitives and the run routes.

### Modified Capabilities

None.

## Impact

- New `server/` folder (Bun, TypeScript, no framework).
- Fork files in `Tinycast/Fork/Core/Primitives/`, `Tinycast/Fork/Core/Workflows/` and
  `Tinycast/Fork/Lyra/`.
- Tagged hooks in the Automation catalog, runner and URL handling, and in
  `QuickActionCoordinator.run`.
- The native Quick Action flow stays in the code as the fallback while the server is down.
