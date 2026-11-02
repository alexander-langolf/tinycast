## Why

Quick AI's Claude route starts a new `claude -p` process for every turn. A spawn that only answers
`initialize` takes ~3.6 s before any model call. The route also flattens the whole conversation
into one text prompt, so earlier turns never reach the model as real messages.

ThinkRail (JetBrains, v0.2.0) skips the CLI entirely. It embeds the `pi` agent library, signs in
with the Claude account through OAuth, and calls the Messages API directly with that token. This
change copies ThinkRail's Claude integration into Tinycast: the sign-in, the model catalog, the
effort ladders and the request shape.

## What Changes

- A fork-owned Claude account sign-in uses ThinkRail's OAuth PKCE (Proof Key for Code Exchange)
  flow, client ID, scopes and token endpoint. Tokens live in the Keychain and refresh before they
  expire.
- Signing in adds one built-in API connection, "Claude account". Its model list is pi's bundled
  Anthropic catalog: the same 17 models, names, order and effort levels that ThinkRail's picker
  shows.
- A model that the API refuses with 404 disappears from the picker. An effort level that the API
  refuses as invalid disappears from that model's ladder. Signing in again restores both.
- A fork-owned request builder ports pi's `buildParams`:
  - the Claude Code identity (headers and the first system block);
  - prompt caching;
  - three effort shapes by model generation;
  - thinking with tools, which keeps thinking signatures within a turn;
  - Claude Code tool-name mapping.
- Chat titles on that connection use the cheapest catalog Haiku model.
- The Claude CLI route, Quick AI handoff and Claude session chat do not change.

## Capabilities

### New Capabilities

- `claude-account-chat`: signing in with a Claude account, the built-in connection and its
  catalog, the request shape, token refresh, refusal handling and failure messages.

### Modified Capabilities

None. Every other connection keeps its request shape and model list.

## Impact

- New fork folder `Tinycast/Fork/ClaudeAccount/`: sign-in, token store, refresh, catalog, request
  builder, stream observer, connection registration and the provider.
- `// FORK: claude-account` hooks:
  - `AIProviderFactory.swift`: the provider for the account's connection.
  - `AIModelOption.swift`: catalog names in the picker.
  - `AIModelDiscovery.swift`: Refresh re-applies the catalog.
  - `AIChatCoordinator.swift`: the title model.
  - `KeychainSecretStore.swift`: the scope list.
  - The AI Settings providers view: the account row.
  - The connection removal path: sign-out.
- `AppCore.swift` owns the account and registers the connection at launch.
- `Tests/` gains a claude-account harness registered in `Scripts/run-tests.sh`.
- `docs/fork.md` gains a "Claude account chat" section and the new hooks in its table.
