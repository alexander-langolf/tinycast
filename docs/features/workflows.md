# Workflow server

Tinycast runs Rewrite, Fix Grammar, and Lyra selection Fix through the Bun server in `server/`.
The server owns action steps, prompts, and policy.
Tinycast owns native selection access, model providers, replacement, previews, markers, and messages.

## Invariants

- The server listens on loopback and requires its bearer token for every route.
- The Automation client has the `selection`, `model`, and `ui` scopes.
- Target handles and UI interactions belong to the authenticated client.
- Handles expire after two minutes and permit one replacement attempt.
- Replacement validates the captured application, focused element, field value, and selection.
- A selection without a verifiable Accessibility snapshot supports reading and preview copying, but refuses replacement and markers.
- Events contain fixed metadata, counts, and correlation identifiers without user text or credentials.
- Run links require a link-safe catalog entry and the server enforces preview or marker interaction.
- Shutdown cancels pending interactions and stops only the owned Bun child.

## Lifecycle

`AppCore` owns `ForkWorkflowServer` and `ForkPrimitives`.
The Debug workflow server starts when Automation starts.
Release builds use the native Quick Action fallback.
The server directory preference is `fork.server.directory`, with `~/github/tinycast/server` as its default.
The Bun executable is `~/.bun/bin/bun`.
The Dev listener uses port 43322.
The child receives the actual channel Automation port through `TINYCAST_PORT`.

`AutomationClientStore.ensureWorkflowsClient` provisions the built-in client under the store's mutation lock.
The bundle-scoped `fork.workflows.clientID` preference identifies the client independently of its display label.
The method repairs the scopes, expiry, metadata, Keychain token, and authentication digest.
The server token lives at `Application Support/<bundle>/Workflows/server-token` with permissions `0600`.
The process receives both tokens through environment variables.

`ForkProcessSupervisor` owns process readiness and termination.
The workflow owner probes health every two seconds and permits three restarts within ten minutes.
The health resource includes the workflow process state and action count.
An occupied port prevents a new launch.
Tinycast does not adopt an unrelated listener.

## Calling actions

Scripts call authenticated `POST /actions/<name>` with an optional `target` bundle identifier.
`GET /actions` returns the action catalog.
`GET /health` returns the server status and action count.
The [server README](../../server/README.md) provides a direct request example.

`tinycast://run/rewrite` and `com.tinycast.app.dev://run/lyra-fix-selection` forward through Tinycast.
The URL handler captures the frontmost application's bundle identifier.
The handler checks the server catalog before forwarding with `X-Tinycast-Source: link`.
The server checks link safety again.
A caller-supplied `fromLink` body field is refused.

External Rewrite and Fix Grammar shortcuts use the server while health succeeds.
The Notes editor, custom actions, Translate, and Summarize use the native flow.
A failed health check shows “The workflow server is not running; using the built-in action” and runs the native action.
A server action failure reports an error without starting a second transformation.

## Native primitives

| Tool | Scope | Result |
| --- | --- | --- |
| `selection_read` | `selection` | Selected text, source, bundle identifier, and target handle. |
| `model_complete` | `model` | Completed model text. |
| `text_replace` | `selection` | Replacement acknowledgement through `applied`. |
| `ui_preview` | `selection` | Interaction identifier for the Quick Action result panel. |
| `ui_marker` | `selection` | Interaction identifier for the Lyra marker and Tab flow. |
| `ui_result` | `selection` | Pending state or the final choice; optional cancellation. |
| `hud_show` | `ui` | Message acknowledgement. |

`model_complete` accepts a connection, instructions, text, and an optional integer token limit from 1 to 32,768.
`quickActions` uses the shared Quick Actions model route.
`lyra` and `local` select Local Lyra and require Lyra to be enabled.
A connection name selects the first model in that connection.
Providers come from `AIProviderFactory` and must return complete, nonempty text.

Previews support Replace, Copy, and Dismiss.
Markers support the existing first-Tab preview and second-Tab application.
`ui_result` returns `replace`, `copy`, `applied`, or `dismissed` when interaction finishes.
The server polls every 250 milliseconds and cancels the interaction when the action ends.
Native interactions expire after two minutes.
Replacement rechecks handle expiry at the write boundary.

## Configuration and diagnostics

`server/policy/lyra.json` and `server/prompts/` also supply typed Lyra and its rewrite panel.
The Lyra policy directory preference points to the server root.
The bundle contains the same policy and prompt folders as the fallback.
The server watches action, prompt, and policy files and retains valid definitions when an edit fails validation.

`X-Tinycast-Correlation` carries one UUID across the action and every primitive request.
Automation adopts the UUID for `ForkTrace`.
The server writes `Diagnostics/server.jsonl` with the `ForkEvent` schema.
`tinycast logs` merges native and server records by timestamp and follows both rotation series.

The workflow harness covers expiry, ownership, changed-field refusal, model arguments, link safety, and environment construction.
