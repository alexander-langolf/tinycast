> Each group names its files, its done check, and the design decision it implements. Run
> `./Scripts/run-tests.sh` and `Scripts/fork-audit.sh` after each group. Tests in group 8 come
> after Sasha's Dev check in group 7.

## 1. Sign-in and token store

- [x] 1.1 Add `static let claudeAccount = KeychainSecretStore(scope: "claude-account")` to
  `Tinycast/Platform/KeychainSecretStore.swift` (`// FORK: claude-account`). Create
  `Tinycast/Fork/ClaudeAccount/ForkClaudeAccountStore.swift`. It holds
  `{access, refresh, expires}` in that store, and it computes `expires` as
  `now + expires_in − 300 s` (design §2).
- [x] 1.2 Create `ForkClaudeAccountLogin.swift` with PKCE, the authorize URL, the loopback callback
  server (port 53692, then any free port), the copy-code parser for `code#state`, and the token
  exchange (design §1). A state mismatch throws.
- [x] 1.3 Create `ForkClaudeAccount.swift`, an `@MainActor` observable owner. It exposes a phase
  (signed out, signing in, signed in, failed), `signIn()`, `submitCode(_:)`, `signOut()` and
  `accessToken() async throws`. That method runs one shared refresh task (design §2).
- [ ] 1.4 Done when a scratch `#if DEBUG` entry point signs in against the real endpoint and prints
  the token's expiry, never the token.

## 2. Catalog and connection

- [x] 2.1 Create `ForkClaudeCatalog.swift` with the 17 entries copied from pi's `anthropic.json`
  (bundle line 92398): `id`, `name`, `contextWindow`, `maxTokens`, `thinkingLevelMap`,
  `supportsMidConvoEffort` and `forceAdaptiveThinking`. Add the ladder rule and the default level
  `medium` (design §3).
- [x] 2.2 Create `ForkClaudeAccountSettings.swift` to store the connection ID and the refusals
  (design §4, §9).
- [x] 2.3 On sign-in, add or restore the "Claude account" `AIConnection` with the catalog's models
  and ladders, minus refusals. On sign-out, remove the connection. Removing the connection in
  Settings calls `signOut()` (`// FORK: claude-account`).
- [x] 2.4 `AIModelOption.swift`: show catalog names for the account's connection
  (`// FORK: claude-account`).
- [x] 2.5 `AIModelDiscovery.swift`: Refresh on the account's connection clears refusals and
  re-applies the catalog instead of calling `/v1/models` (`// FORK: claude-account`).
- [x] 2.6 `AppCore.swift`: own `ForkClaudeAccount` and register the connection at launch when
  tokens exist (`// FORK: claude-account`).

## 3. Request body

- [x] 3.1 Create `ForkClaudeCodeTools.swift` with ThinkRail's 17 built-in names and the two
  mapping functions (design §7).
- [x] 3.2 Create `ForkClaudeRequestBody.swift`. It builds the system array, the structured
  messages, the tools with `eager_input_streaming`, and the cache marks (design §6).
- [x] 3.3 Add the three effort shapes, the betas each one adds, the budgets and the `max_tokens`
  rule (design §6 table). Record each assistant message's effort for the system-role effort
  messages.

## 4. Provider

- [x] 4.1 Create `ForkClaudeStreamObserver.swift`. It collects thinking text, signatures and
  redacted thinking per following tool call from the raw SSE lines (design §8).
- [x] 4.2 Create `ForkClaudeAccountProvider.swift` (design §5). It awaits the token, sends the
  headers, builds the body, and streams through the upstream `AIStreamDecoder` and the observer.
  It maps tool-call names back, puts the current turn's thinking blocks back in later rounds, and
  retries once after a 401 that arrives before the first event.
- [x] 4.3 Read the CLI version once per launch from `claude --version` through
  `ForkAIExecutableResolver`, with fallback `2.1.280`.
- [x] 4.4 `AIProviderFactory.swift`: in the `.api` case, return the provider for the account's
  connection ID (`// FORK: claude-account`).

## 5. Failures

- [x] 5.1 Map a 404 that names the model and a 400 "Invalid effort level" to a recorded refusal
  and a failure message that says the item is now hidden (design §9).
- [x] 5.2 Map a 429 to the failure message that names the Claude CLI route. Check that the token
  is in the redaction secrets list.

## 6. Titles, Settings and docs

- [x] 6.1 `AIChatCoordinator.swift` title request (~line 264): on the account's connection, use
  the first catalog Haiku model that is not refused, with no thinking (design §10,
  `// FORK: claude-account`).
- [x] 6.2 AI Settings providers view: add a Claude account row with Sign In, Sign Out, the
  copy-code field, and the phase text (`// FORK: claude-account`).
- [x] 6.3 `docs/fork.md`: add a "Claude account chat" section and list every new hook in the
  Upstream hooks table.

## 7. Dev check (Sasha)

- [ ] 7.1 Build Tinycast Dev. Sign in, and compare the model picker and each effort menu with
  ThinkRail's.
- [ ] 7.2 Send two turns each on Haiku 5.5, Sonnet 5.5, Opus 5.5 and Sonnet 4.5 in Quick AI.
- [ ] 7.3 Pick Opus 4.8, then Sonnet 5.5 at Max. Each turn fails once, and the model or the level
  disappears.
- [ ] 7.4 Run one Opus 5.5 chat with an MCP tool attached, and confirm that the tool loop
  completes.
- [ ] 7.5 Compare time to first token on Sonnet 5.5 between this connection and the Claude CLI
  route (three sends each).
- [ ] 7.6 Sign out, sign in again, and confirm that the saved chat selection still works.

## 8. Harness

- [ ] 8.1 Add `Tests/claude-account-test.swift`, registered in `Scripts/run-tests.sh`. It covers:
  - the ladder for every catalog model;
  - the body for each effort shape, including budgets, betas and system-role effort messages;
  - the cache marks;
  - the tool-name mapping both ways;
  - thinking-block replay within a turn and its absence across turns;
  - refusal parsing and hiding, and Refresh clearing refusals;
  - the copy-code parser and the expiry arithmetic;
  - the single-flight refresh, and 401 retry and sign-out with a stub transport.
- [ ] 8.2 Done when `./Scripts/run-tests.sh` and `Scripts/fork-audit.sh` pass.
