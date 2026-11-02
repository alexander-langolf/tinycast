## Context

Today Rewrite runs this way:

1. `QuickActionCoordinator.run` (`Features/QuickActions/UI/QuickActionCoordinator.swift:178`)
   resolves the target from palette state and hides the palette.
2. `QuickActionRunner.selection` reads the selection.
3. `QuickActionPrompt` supplies compiled prompts.
4. `core.quickActionProvider(for:)` and `QuickActionRunner.run` stream the model reply.
5. `present` shows the diff panel, or `showProgress` shows the HUD.
6. `TextInjector.replaceSelection` delivers the reply, with a clipboard fallback.

Earlier slices added the following:

- `ForkTrace` with correlation IDs;
- `ForkProcessSupervisor`;
- the `selection` scope, `selection_read`, `quick_action_run` and `tinycast call`;
- router tracing;
- Lyra's marker UI;
- `fork-policy-split`'s `policy/` folder and `lyra_offer`.

Automation clients authenticate with bearer tokens stored in the Keychain
(`AutomationClientStore`). `AutomationURL` lets links reach only operations whose catalog entry
has a link host.

Bun 1.4.2 is installed at `~/.bun/bin/bun`.

## Goals / Non-Goals

**Goals:**

- A workflow's steps, prompts and conditions change without a Tinycast build or restart.
- BetterTouchTool, Script Kit and Tinycast run the same action.
- One correlation ID covers a run across the server and Tinycast.

**Non-Goals:**

- Moving Summarize, Translate, custom Quick Actions or Lyra's typed Fix-on-pause and panel. Later
  changes port them onto the same primitives.
- Deleting the native Quick Action flow. It remains the fallback.
- A release-build server bundle. The server runs from the repository for Dev.

## Decisions

### 1. Primitives are Automation tools

| Tool | Input | Output | Scope |
| --- | --- | --- | --- |
| `selection_read` (extended) | `target` (optional bundle ID) | `{text, source, bundleID, handle}` | `selection` |
| `model_complete` | `connection` (`"quickActions"`, `"lyra"`, a connection name or `"local"`), `instructions`, `text`, optional `maxTokens` | `{text}` | new `model` |
| `text_replace` | `handle`, `text` | `{applied}` | `selection` |
| `ui_preview` | `handle`, `title`, `original`, `text`, `showsDiff` | `{id}` | `selection` |
| `ui_marker` | `handle`, `text` | `{id}` | `selection` |
| `ui_result` | `id`, optional `cancel` | `{pending, choice}`; the choice is `replace`, `copy`, `applied` or `dismissed` | `selection` |
| `hud_show` (existing) | `text` | `{shown}` | `ui` |

A handle names the target app, the focused element and the selection range at read time.
Tinycast keeps handles for 2 minutes. `text_replace` refuses a handle whose field changed, using
Lyra's pre-write checks. `ui_preview` reuses the Quick Action panel with its diff and its Replace
and Copy buttons. `ui_marker` reuses Lyra's marker and its Tab flow. Both return an interaction ID at once. The action polls
`ui_result` until the user acts, and cancels the interaction when the action ends. Each primitive request stays within the Automation handler deadline of 180 seconds.

`model_complete` routes through `AIProviderFactory`: `quickActions` uses the Quick Actions
connection, `lyra` and `local` use the Local Lyra connection, and a name selects that connection.

### 2. The server is plain Bun

`server/src/main.ts` serves HTTP on `127.0.0.1` at a port from `TINYCAST_SERVER_PORT` (Dev
43322). It has these routes:

- `GET /health`;
- `GET /actions`, which lists each action with its title and whether it is link-safe;
- `POST /actions/:name`, with a JSON body of arguments.

Each request needs `Authorization: Bearer $TINYCAST_SERVER_TOKEN`.

Each action is a file in `server/actions/` that exports `meta` (`title`, `linkSafe`) and
`run(ctx, args)`. `ctx` provides typed wrappers for the primitives, `ctx.prompt(name)` reading
`server/prompts/<name>.txt`, `ctx.policy` reading `server/policy/*.json`, and `ctx.log`.

The server watches `actions/`, `prompts/` and `policy/`. It imports a changed action through a temporary module in the resolved action directory and validates its exports. When validation fails, it keeps the last valid
version and logs the rejection.

### 3. Tinycast launches and authorises the server

`ForkWorkflowServer` runs `~/.bun/bin/bun run src/main.ts` in `fork.server.directory` (default
`~/github/tinycast/server`) under `ForkProcessSupervisor`. At launch it does the following:

- It creates a random `TINYCAST_SERVER_TOKEN` and writes it to
  `Application Support/<bundle>/Workflows/server-token` with `0600` permissions, for Script Kit.
- It ensures a built-in Automation client with the `selection`, `model` and `ui` scopes, and
  passes its token as `TINYCAST_TOKEN`. A tagged `ensureWorkflowsClient` method on
  `AutomationClientStore` creates or repairs the client under the store's mutation lock. The
  client is identified by an ID stored in a bundle-scoped preference, never by its label.
- It passes `TINYCAST_PORT` and `TINYCAST_SERVER_PORT`.

The health resource lists the server with its state and its action count.

### 4. One correlation ID per run

A caller may send `X-Tinycast-Correlation`. Otherwise the server creates one. The server sends it
on every primitive call. `AutomationRouter` adopts it for the call's `ForkTrace`. The server
writes its own events to `Diagnostics/server.jsonl` with the `ForkEvent` field names, and
`tinycast logs` merges both files by time.

### 5. Run routes

- **Script Kit and scripts** post to the server, with the token read from the token file.
- **Links:** Tinycast handles `tinycast://run/<name>` and the channel's own scheme. It forwards
  the run to the server only when `GET /actions` marks the action link-safe. The forwarding call
  sends the frontmost app as `target`.
- **BetterTouchTool** uses an Open URL action with that link.
- **Tinycast:** `QuickActionCoordinator.run` sends Rewrite and Fix Grammar to the server when the
  server is healthy (`// FORK: workflow-server`). When the server is down, it shows a HUD, "The
  workflow server is not running; using the built-in action", logs the fallback and runs the
  native flow.

### 6. The first actions

- `rewrite.ts` and `fix-grammar.ts` do the following:
  1. `selection_read`;
  2. `hud_show` the progress title;
  3. `model_complete` with the `quickActions` connection and the prompt file, carried over
     verbatim from `QuickActionPrompt`;
  4. `ui_preview` when the action's setting asks for a preview, otherwise `text_replace`, then
     `hud_show` "Rewrite applied".

  The preview setting is `server/policy/quick-actions.json`. Both actions are link-safe.
- `lyra-fix-selection.ts` does the following:
  1. `selection_read`;
  2. a check of the selection against `policy/lyra.json` `selection` limits;
  3. `model_complete` with the `lyra` connection and the fix prompt;
  4. `ui_marker`.

  It is link-safe.

`fork-policy-split`'s `policy/` folder moves to `server/policy/` and `server/prompts/`. Its
in-app policy store keeps serving Lyra's typed Fix until that flow moves. `lyra_offer` is
replaced by the `lyra-fix-selection` action.

### 7. Tests

- `bun test` covers each action against fake primitives, plus the reload, rejection and
  last-valid behaviour.
- Swift harnesses cover handle expiry and the changed-field refusal, `model_complete` argument
  validation, link-safety forwarding, and the server environment.

## Risks / Trade-offs

- **An extra process on the critical path.** The supervisor restarts it, and Tinycast falls back
  to the native flow for its own hotkeys.
- **Polling.** `ui_result` polling adds a small delay between the user's choice and the action's
  next step.
- **Link safety.** A link-safe action is visible to any app that opens a URL. Only actions that
  end in a preview or a marker are link-safe.
