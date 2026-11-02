## Context

Quick AI reaches Claude in two ways. The Claude CLI route (`InstalledCLIProvider`) spawns
`claude -p --no-session-persistence` for each turn and sends the conversation as one flattened
prompt. The Anthropic API route (`HTTPAIProvider` with the `.anthropic` shape) streams
`/v1/messages` with an `x-api-key`. `AIStreamDecoder.decodeAnthropic` reads text, thinking, tool
calls and cache usage. `AIChatCoordinator` wraps any provider in `AIToolLoopProvider`, so an API
connection already calls Tinycast's MCP (Model Context Protocol) tools. An `AIConnection` holds
its model IDs in `models` and its effort levels per model in `reasoningOptions`.

ThinkRail embeds `@earendil-works/pi-ai` 1.2.0. These are the relevant places in
`/Applications/ThinkRail.app/Contents/Resources/app/runtime/server-runtime.ts`:

| Line | Code |
| --- | --- |
| 517116 | The Anthropic OAuth provider: URLs, client ID, scopes, exchange and refresh. |
| 101431 | The Anthropic provider: a fixed model list with no live fetch. |
| 92398 | The bundled Anthropic catalog (`providers/data/anthropic.json`). |
| 36724 | `getSupportedThinkingLevels`: the effort ladder rule. |
| 38086–38300 | `createClient`, `getBetaFeatures` and `buildParams`: headers, betas and body. |
| 38476 | `insertThinkingLevelMessages`: effort as system-role messages. |
| 38541 | Claude Code tool names and the rename functions. |
| 37613 | Thinking budgets per level for budget-based models. |

The following results come from direct API calls on 2026-10-28 with an enterprise Claude account
token.

| Request | Result |
| --- | --- |
| Haiku 4.5, bearer token, no Claude Code identity | 200 in 0.43 s |
| Sonnet 5.5 or Opus 5.5, bearer token, no Claude Code identity | 429 `rate_limit_error` |
| Sonnet 5.5 with only the `claude-code-20250219` beta header | 429 |
| Sonnet 5.5 with only the `claude-cli` user agent and `x-app: cli` | 429 |
| Sonnet 5.5 with only the identity sentence as the first system block | 200 |
| Sonnet 5.5 with the identity sentence as the prefix of a single system string | 429 |
| Sonnet 5.5 with the identity block second | 429 |
| Each of the 17 catalog models with the full identity | 200 for 8 models, 404 for 9 |
| Sonnet 5.5 with effort `low`, `medium` or `high` | 200 |
| Sonnet 5.5 with effort `xhigh` or `max` | 400 "Invalid effort level" |
| Opus 5.5, Fable 5.1 and Haiku 5.5 with effort `low`, `high`, `xhigh` or `max` | 200 |
| Sonnet 5.5 with a system-role effort message and the two mid-conversation betas | 200 |
| Sonnet 4.5 with budget thinking (1,024 tokens) | 200 with a thinking block |
| Sonnet 5.5 with a custom tool name and automatic tool choice | 200 with `tool_use` |
| Sonnet 5.5 with forced tool choice (`any`) | 400: unsupported for this model |
| Two identical requests with a cached system block | 9,832 tokens written, then 9,832 read |

These 8 models answer: `claude-fable-5-1`, `claude-haiku-4-5`, `claude-haiku-4-5-20251001`,
`claude-haiku-5-5`, `claude-opus-5-5`, `claude-sonnet-4-5`, `claude-sonnet-4-5-20250929` and
`claude-sonnet-5-5`. These 9 return 404: `claude-fable-5`, `claude-opus-4-5`,
`claude-opus-4-5-20251101`, `claude-opus-4-6`, `claude-opus-4-7`, `claude-opus-4-8`,
`claude-opus-5`, `claude-sonnet-4-6` and `claude-sonnet-5`. `GET /v1/models` lists six of the
nine, so the model list cannot come from that endpoint.

The server unlocks models above Haiku only when the first system block is exactly the identity
sentence. The headers do not affect that check. The route sends them anyway so that its requests
match ThinkRail's.

## Goals / Non-Goals

**Goals:**

- The model picker on the account's connection lists ThinkRail's models, names, order and effort
  levels, minus anything the API refuses.
- Every request matches the body and headers that pi builds for the same model and effort.
- Multi-turn history reaches the model as structured messages, with prompt caching on.
- Sign-in, refresh and sign-out work without a terminal.
- Every other route keeps its behaviour.

**Non-Goals:**

- ThinkRail's coding tools (Bash, Edit, Read through `pi`). The connection gets only the MCP tools
  that the chat already attaches.
- The picker's detail line ("plan · 1M"). Tinycast's model option has a title only.
- pi's inline tool changes (`inline-tools-2026-09-15` and the deferred-tool placeholder). A
  Tinycast chat's tool set stays fixed for the whole request.
- Server-side fallback models. Only `claude-fable-5` declares them, and that model returns 404.
- A warm root for this connection. A request has no process to start.
- Changing the Claude CLI route, Quick AI handoff or Claude session chat.

## Decisions

### 1. Tinycast runs its own sign-in

`ForkClaudeAccountLogin` copies ThinkRail's browser flow:

- PKCE with an S256 challenge, and the verifier doubles as `state`.
- Authorize URL `https://claude.ai/oauth/authorize` with `code=true`, `response_type=code`, client
  ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, and scopes
  `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`.
- A loopback callback server on `127.0.0.1:53692/callback`. When that port is taken, the server
  takes any free port. The redirect URI names host `localhost`.
- A copy-code fallback with redirect URI `https://platform.claude.com/oauth/code/callback`. The
  user pastes `code#state` into a Tinycast field.
- The token exchange posts JSON to `https://platform.claude.com/v1/oauth/token` with
  `grant_type=authorization_code`, `client_id`, `code`, `state`, `redirect_uri` and
  `code_verifier`.

Tinycast never reads or refreshes Claude Code's own Keychain item. A refresh rotates the refresh
token, so sharing that item would sign Claude Code out.

### 2. Tokens live in one Keychain item and refresh once at a time

`ForkClaudeAccountStore` keeps `{access, refresh, expires}` in a `KeychainSecretStore` with scope
`claude-account`. The scope joins the list in `KeychainSecretStore.swift`, which names every scope
the app stores under. `expires` is `now + expires_in − 5 minutes`, as in ThinkRail. A request that
finds the token expired awaits one shared refresh task. The refresh posts
`grant_type=refresh_token`, `client_id` and `refresh_token` to the token endpoint. A refused
refresh deletes the item and leaves the account signed out.

### 3. The catalog is a fork-owned copy of pi's table

`ForkClaudeCatalog.swift` holds the 17 entries of pi's `anthropic.json` in its order. Each entry
keeps `id`, `name`, `contextWindow`, `maxTokens`, `thinkingLevelMap` and the `compat` flags
`supportsMidConvoEffort` and `forceAdaptiveThinking`.

pi's ladder rule decides each model's levels. The full ladder is off, minimal, low, medium, high,
xhigh, max. A level mapped to `null` is dropped. Xhigh and max appear only when the map names
them. Tinycast stores the ladder in `reasoningOptions[model]` with `none` for pi's off, and the
default level is `medium`, pi's `DEFAULT_THINKING_LEVEL`.

### 4. The route is a built-in API connection

Signing in creates one `AIConnection` with provider `.anthropic`, base URL
`https://api.anthropic.com` and title "Claude account". Its `models` and `reasoningOptions` come
from the catalog, minus recorded refusals (decision 9). `ForkClaudeAccountSettings` stores its ID
and the refusals. The picker, effort menu, route switch and tool loop all treat it as an API
connection. A `// FORK: claude-account` hook in `AIModelOption` shows catalog names instead of
IDs. Refresh on this connection re-applies the catalog instead of calling `/v1/models`. Removing
the connection signs out, and signing out removes the connection. Signing in again reuses the
stored ID, so saved chat selections keep working.

### 5. A fork-owned provider sends the request

`AIProviderFactory.make` returns `ForkClaudeAccountProvider` for the account's connection ID,
behind a `// FORK: claude-account` hook. The provider owns its `URLRequest`. It streams with
`URLSession` and feeds each line to the upstream `AIStreamDecoder` with the `.anthropic` shape. It
does the following for each stream:

1. It awaits a fresh access token.
2. It sends the headers that pi sends for an OAuth token:
   - `Authorization: Bearer <token>`, with no `x-api-key`;
   - `anthropic-version: 2023-06-01`;
   - `user-agent: claude-cli/<version>` and `x-app: cli`;
   - `anthropic-beta` with `claude-code-20250219` and `oauth-2025-04-20`, plus the betas from
     decision 6.
3. It builds the body with `ForkClaudeRequestBody` (decision 6).
4. A 401 before the first event triggers one refresh and one retry. A second 401 signs the
   account out.

`<version>` comes from `claude --version` through `ForkAIExecutableResolver`, read once per launch.
The fallback is ThinkRail's `2.1.280`.

### 6. The body ports pi's `buildParams`

`ForkClaudeRequestBody` builds:

- `model`, `stream: true`, and `max_tokens`. The value is the catalog's `maxTokens`, or the
  adjusted value for budget thinking.
- `system`: the identity block first, then one block with the joined instructions and system
  messages. Both blocks carry `cache_control: {type: "ephemeral"}`.
- `messages`: the conversation as structured user, assistant, tool-use and tool-result content.
  The last content block of the latest user message carries `cache_control`.
- `tools`: each tool with `eager_input_streaming: true`, and `cache_control` on the last tool.
  Names follow decision 7.

The effort shape depends on the model's `compat` flags:

| Model flags | Thinking and effort | Extra betas |
| --- | --- | --- |
| `supportsMidConvoEffort` | `thinking: {type: "adaptive", display: "summarized", block_binding: {prefix_mismatch_behavior: "drop_block"}}` and `output_config: {effort: "high"}`. The messages also carry a system-role `output_config` message with the chosen effort after the last message, and one before each earlier assistant message with that message's effort. | `mid-conversation-output-config-2026-07-01`, `thinking-binding-controls-2026-08-01` |
| `forceAdaptiveThinking` only | A level other than off sends `thinking: {type: "adaptive", display: "summarized"}` and `output_config: {effort}`. Off sends no thinking field. | `interleaved-thinking-2025-05-14` is not sent. |
| Neither flag | A level other than off sends `thinking: {type: "enabled", budget_tokens, display: "summarized"}`. The budget is 1,024 for minimal, 2,048 for low, 8,192 for medium and 16,384 for high. `max_tokens` becomes the smaller of the budget plus the catalog's `maxTokens` and the catalog's `maxTokens`. Off sends `thinking: {type: "disabled"}`. | `interleaved-thinking-2025-05-14` for every level except off |

Each assistant message records the effort it ran with, so later requests can rebuild the
system-role effort messages.

### 7. Tool names follow ThinkRail's mapping

ThinkRail renames a tool whose name matches a Claude Code built-in tool, ignoring case, to the
built-in spelling. The list is Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion,
EnterPlanMode, ExitPlanMode, KillShell, NotebookEdit, Skill, Task, TaskOutput, TodoWrite, WebFetch
and WebSearch. The body applies the rename to request tools and to earlier tool calls in the
history. The provider maps tool-call names in stream events back to the request's tool name. Names
outside the list pass through unchanged.

### 8. Thinking signatures survive a tool loop

A `ForkClaudeStreamObserver` reads the same SSE lines as the decoder. It collects each thinking
block's text and `signature`, and the redacted thinking blocks, keyed by the tool call that
follows them. `AIToolLoopProvider` calls the provider again for each round of one turn. The
provider then puts those blocks back in front of the matching `tool_use` blocks. Blocks are kept
for the current turn only. pi does the same through `block_binding`, which drops thinking from
earlier turns.

### 9. Refusals hide models and levels

A 404 whose message names the model marks that model refused. A 400 with the message "Invalid
effort level" marks that model and level refused. `ForkClaudeAccountSettings` records each refusal
and removes the item from the connection's `models` or `reasoningOptions`. The turn fails with the
API's message and a note that the item is now hidden. Signing in again, or Refresh on the
connection, clears the refusals and re-applies the full catalog.

### 10. Titles use Haiku

`AIChatCoordinator` asks the selected route to name a chat, with `ChatTitle.instructions`. On the
account's connection, a `// FORK: claude-account` hook in that request swaps in the first catalog
Haiku model that is not refused. Title requests send no thinking.

## Risks / Trade-offs

- **The server check can change.** Anthropic can tighten the identity check at any time. The route
  then fails with 429, and the failure message names the Claude CLI route as the alternative.
- **The catalog goes stale.** The table is a copy of pi 1.2.0. New models need a manual update of
  `ForkClaudeCatalog.swift`.
- **Account terms.** Anthropic limits Claude account OAuth tokens to Claude Code and Claude.ai.
  The route requires an explicit sign-in and stays off until then.
- **Callback port.** Port 53692 matches ThinkRail and pi. When both apps sign in at once, the
  second one falls back to a free port.
