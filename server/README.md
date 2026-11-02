# Tinycast workflow server

Bun runs actions from `actions/`, prompts from `prompts/`, and policy from `policy/`.
Tinycast Dev supervises the server when Automation is enabled.
The native tools remain in Tinycast.

## Direct calls

The Dev server listens at `http://127.0.0.1:43322`.
Every route requires the bearer token in `~/Library/Application Support/com.tinycast.app.dev/Workflows/server-token`.

```sh
TINYCAST_WORKFLOW_TOKEN=$(cat "$HOME/Library/Application Support/com.tinycast.app.dev/Workflows/server-token")
curl --fail-with-body http://127.0.0.1:43322/actions \
  -H "Authorization: Bearer $TINYCAST_WORKFLOW_TOKEN"
curl --fail-with-body http://127.0.0.1:43322/actions/rewrite \
  -H "Authorization: Bearer $TINYCAST_WORKFLOW_TOKEN" \
  -H 'Content-Type: application/json' --data '{}'
```

The selected text comes from the focused external application.
An optional `target` body field constrains that application's bundle identifier.
The catalog exposes each action's `name`, `title`, and `linkSafe` flag.
The health route returns `status` and `actionCount`.
One action runs at a time; concurrent runs receive HTTP 409.

BetterTouchTool uses an Open URL action with `com.tinycast.app.dev://run/lyra-fix-selection`.
Tinycast checks the catalog and forwards link-safe actions with the frontmost application as the target.
Link calls force a preview or marker before replacement.
Direct Rewrite and Fix Grammar calls follow `policy/quick-actions.json`.

## Native contract

`src/context.ts` calls the authenticated Tinycast Automation endpoint at `/mcp`.
The supervisor supplies `TINYCAST_TOKEN`, `TINYCAST_PORT`, `TINYCAST_SERVER_TOKEN`, `TINYCAST_SERVER_PORT`, and `TINYCAST_DIAGNOSTICS_DIRECTORY`.
The client uses selection handles and asynchronous UI interaction identifiers.
The client polls `ui_result` until completion and cancels abandoned interactions.
The [workflow guide](../docs/features/workflows.md) lists the primitive arguments and lifecycle rules.

## Development

An action exports `meta` with `title` and `linkSafe`, plus an asynchronous `run(ctx, args)` function.
The catalog imports each changed source through a temporary module in the resolved action directory.
Invalid source or exports preserve the last valid action.
Policy and prompt validation preserves the last valid configuration snapshot.

```sh
cd server
~/.bun/bin/bun test
```

`X-Tinycast-Correlation` accepts a UUID or the server creates one.
Native requests carry the same identifier.
Events contain fixed fields and numeric lengths without selected text, prompts, output, or tokens.
`tinycast logs --id <uuid> --channel dev` reads both native and server events.
