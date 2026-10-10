# Quick AI Root Session and Start Work: implementation plan

> **For agentic workers:** work group by group. Codex implements each group from its brief and runs no
> builds, tests, formatters or commits. Claude builds, runs `Scripts/lint.sh` and
> `Scripts/fork-audit.sh`, relaunches Dev and commits between groups. Checkboxes (`- [ ]`) track
> progress. This is a **fork** feature, so read `docs/fork.md` first. Fork code lives in
> `Tinycast/Fork/QuickAIRoot/`. Upstream files get only `// FORK: quick-ai-root` hooks, each with a
> `docs/fork.md` row. **No tests until Sasha has verified the behaviour (Group 6).** Work on branch
> `al/quick-ai-root` and merge into `main` after verification. No worktrees. Never send synthetic
> input; visual checks use `screencapture -l` of Dev windows only.

**Goal and behaviour:** see `docs/features/quick-ai-root-session.md`, which is the spec. That doc
wins if this plan disagrees with it.

**Architecture in one line:** Start Work opens a terminal instance running interactive `claude` or
`codex`, whose first prompt is the Quick AI conversation as text, with the first message verbatim
so its sigils resolve there. Separately, a fork-owned `ForkQuickAIRoot` keeps one ephemeral,
read-only Codex thread ready, and `CodexTurnRunner.prepareThread` claims it for Quick AI sends.
There's no engine fork, and nothing is deleted from Codex.

**Verified anchors** (`main` @ `6161df5d`):

| What | Where |
|---|---|
| Thread creation | `CodexTurnRunner.prepareThread`, `Tinycast/Features/AI/Service/CodexTurnRunner.swift:331` (`thread/start` at `:345-355`) |
| Idle shutdown | `ChatGPTSubscriptionManager.scheduleIdleShutdown`, `…/ChatGPTSubscriptionManager.swift:136` (600 s, `:9`) |
| Quick AI state | `AIChatSurfacesState.quickAI`, `…/AI/UI/AIChatSurfacesState.swift:9`; `holds(_:)` at `:55` |
| Request identity | `AIChatState.startReply` sends `conversationID: session.id`, `…/AI/UI/AIChatState.swift:85` |
| Quick AI show / new chat | `QuickAICoordinator.show` `:26`, `startNewChat` `:96`, `.startNew` policy `:84` |
| Quick AI actions and keys | `AIScreen.actions(at:)` `:22`; `secondary(at:)` returns `false`; `tertiary(at:)` falls back to `PaletteScreen`'s default `false` (`Tinycast/Palette/PaletteScreen.swift:179`) |
| Return routing | `RootPaletteView.swift:~573-581` and `:~1216-1222`: ⌃⌘↵ → `tertiary`, ⇧⌘↵ → `copyCalculation` then `secondary`, ⌘↵ → `secondary` |
| Executable lookup | `ExecutableLocator.locate(kind.command, extraHomePaths: kind.extraExecutablePaths)`, as in `InstalledAIManager.swift:193` |
| Terminal launch | `TerminalInstancesCoordinator.open(command:directory:)`, `…/TerminalInstances/UI/TerminalInstancesCoordinator.swift:45` |
| Working folder | `ForkAIWorkingDirectory.url` (`docs/features/ai-working-directory.md`) |

---

## Group 0: Spike (done, 2026-10-10)

- [x] Checked an engine fork (`codex fork` of an app-server thread). It works, but the root's
      text-only instructions travel with the history, forked roots can't be deleted, and a fork
      keeps the root's `cwd`. That's why the spec now moves the chat as text.
- [x] Idle cost of a kept-alive server: negligible (0.08 s CPU in 15 min, about 100 MB).
- [x] Shortcuts: ⌘↵ → `secondary`, ⌃⌘↵ → `tertiary`, both unused in the AI screen.
- [x] Surface check: `chats.quickAI.holds(conversationID)`, with no change to `AIRequest`.

Results are in the spec's *Spike results*.

## Group 1: Settings and the log

- [x] **1.1** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIRootSettings.swift`, holding:
      - `warmRoot: Bool`, default false;
      - `startWorkEngine: off | claude | codex`, default `claude`;
      - `retention: hour | day | week`, default `day`.

      They're stored through the fork's settings pattern.
- [x] **1.2** Add hooks so all three reach `AppSettingsKey`, `SettingsFileKey`/schema,
      `SettingsBackup`/coverage and `ForkSettingsSearch`, mirroring how the appearance tokens were
      wired (`// FORK: quick-ai-root`).
- [x] **1.3** In the Quick AI section of `AISettingsView`
      (`Tinycast/Features/AI/Settings/AISettingsView.swift:~143`), add a one-line hook to a
      fork-owned `ForkQuickAIRootSettingsRows`:
      - the toggle "Keep a warm root session (Codex)", disabled with a note when the provider isn't
        Codex;
      - the "Start Work in" picker, with engines that aren't installed disabled;
      - the "Forget the Quick AI log after" picker.
- [x] **1.4** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIRootLog.swift`:
      - an append-only JSONL at `<Application Support>/QuickAIRoot/log.jsonl`;
      - events `warmed | claimed | retired | handedOff | fellBack`;
      - fields `at`, `event`, and optional `root`, `chat`, `engine`, `terminal`, `reason`;
      - `writeHandoff(chat:text:) -> URL` for `handoffs/<chat id>.md`;
      - a pure `prune(lines:olderThan:)`, plus `pruneFiles(olderThan:)` for handoff files.

      The log never holds message text.
- [x] **1.5** Prune at launch and once an hour (a timer owned by the fork), using the retention
      setting.

**Done when:**
- the settings appear, round-trip through `settings.json` and backups, and search finds them;
- nothing is written to `QuickAIRoot/` while everything is off.

## Group 2: Start Work

Doesn't depend on the root. It's the most useful part, so it ships first.

- [ ] **2.1** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIHandoff.swift`, containing pure
      functions:
      - `prompt(messages:pending:limit:) -> Handoff`, where `Handoff` holds `text` and an optional
        `overflow`:
        - the first user message verbatim and first;
        - then, if there's more, a separator and `Sasha:` / `Quick AI:` turns, with attachment
          placeholders;
        - then the spec's closing line;
        - when the text passes 32 KB, the turns go into `overflow` and the text points at the file
          path;
      - `command(executable:prompt:) -> String`, which single-quotes every argument for zsh,
        escaping `'` as `'\''`, with `--` before the prompt.
- [ ] **2.2** Engine resolution: resolve the executable for `claude` and `codex` with
      `ExecutableLocator.locate(kind.command, extraHomePaths: kind.extraExecutablePaths)`, cached
      per launch. A missing engine hides its action.
- [ ] **2.3** Hook `AIScreen.actions(at:)` (`:22`) to add:
      - "Start Work in Claude Code" or "…in Codex", for the default engine (⌘↵);
      - one item for the other engine (⌃⌘↵), shown only when it's installed.

      Use systemImage `hammer`. The items are shown when the chat has a user message or the
      composer has text, nothing is streaming, and the setting isn't Off.
- [ ] **2.4** Hook `AIScreen.secondary(at:)` (default engine) and add `tertiary(at:)` (other
      engine). Each runs the action and returns `true` when it's available, otherwise `false`, as
      today. `PaletteShortcut` and `RootPaletteView` are untouched.
- [ ] **2.5** The action:
      1. takes the messages, plus the composer text as the pending request;
      2. writes the overflow file if there is one;
      3. calls `TerminalInstancesCoordinator.open(command:directory:)` with the working folder, or
         home when none is set;
      4. logs `handedOff(engine:terminal:chat:)`;
      5. clears the composer;
      6. starts a new Quick AI chat, which retires the root once Group 3 exists.

**Done when:** spec acceptance criteria 4 and 5 pass by hand. Criterion 4 matters most: typing
`context> multiverse emails +stardust research create new tokens` and pressing ⌘↵ opens Claude
Code, and its `Sigils parsed:` block shows the sigils resolved.

## Group 3: Root state and claiming

- [ ] **3.1** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIRoot.swift`:
      - an `@MainActor` state machine with states `off`, `warming`, `ready(Root)`,
        `inUse(Root, chat:)` and `unavailable(reason)`;
      - `Root` = `threadID`, `model`, `webSearch`, `instructions` and `startedAt`;
      - a pure reducer plus effects (start a thread, retire, log). `CodexTurnRunner` owns the
        client, so the effects run through a closure it supplies
        (`startThread(params) async throws -> String`).
- [ ] **3.2** Hook `CodexTurnRunner.prepareThread` (`:331`):
      - When `ForkQuickAIRoot.isQuickAI(request.conversationID)` and the root is `ready` with
        matching model, web search and instructions: use its `threadID`, skip `thread/start` and
        `inject_items`, and log `claimed`.
      - Otherwise, today's path runs unchanged. A mismatch retires the root and logs
        `retired(reason: mismatch)`.
- [ ] **3.3** The root's `thread/start` parameters are exactly today's (`ephemeral: true`, the same
      instructions). The fork only changes when the call happens.

**Done when:**
- with the toggle on, a Quick AI send after warming logs `claimed` and makes no `thread/start`;
- with the toggle off, behaviour is byte-for-byte today's.

## Group 4: Keep-alive, prewarm, retire

- [ ] **4.1** Hook `ChatGPTSubscriptionManager.scheduleIdleShutdown` (`:136`): while the warm root
      is on, don't schedule the shutdown. Turning it off re-arms it.
- [ ] **4.2** Hook `QuickAICoordinator.show` (`:26`): when the root is on and isn't `ready` or
      `inUse`, start warming in the background, so showing the palette is never blocked.
- [ ] **4.3** Hook `QuickAICoordinator.startNewChat` (`:96`), and the `.startNew` path at `:84`:
      retire the current root (`retired(reason: newChat)`) and warm the next one.
- [ ] **4.4** App-server exit or relaunch (`CodexAppServerClient.onExit` / `onRelaunch`): the root
      goes `unavailable`, and the current chat falls back to today's path (`fellBack`). The next
      `show` warms again.

**Done when:** spec acceptance criteria 1, 2, 3, 8 and 9 pass by hand.

## Group 5: Docs

- [ ] **5.1** Add a `docs/fork.md` row for every `// FORK: quick-ai-root` hook, and make
      `Scripts/fork-audit.sh` pass.
- [ ] **5.2** In the spec, set the status to "built, experimental" and list each acceptance
      criterion with its result.
- [ ] **5.3** Add a short cross-reference from `docs/features/ai.md` (Quick AI section) to the spec.
- [ ] **5.4** Update the feature row in the vault's `Tinycast.md`.

## Group 6: Sasha verifies

- [ ] **6.1** Sasha runs acceptance criteria 1–9 on Dev, with the settings on and then off.
- [ ] **6.2** Measure the real time to first token, warm and cold, 5 runs each, and record it in the
      spec.
- [ ] **6.3** Merge `al/quick-ai-root` into `main` (merge, never rebase). Pushing needs Sasha's
      go-ahead.

## Group 7: Tests (only after 6.1)

- [ ] **7.1** `Tests/quick-ai-root-test.swift`, covering:
      - reducer transitions (mismatch, crash fallback, retire while in use);
      - log and handoff-file pruning;
      - handoff prompt building: first message verbatim and first, attachment placeholders,
        overflow at 32 KB;
      - command quoting (single quotes, newlines, non-ASCII, a prompt starting with `-`).
- [ ] **7.2** Add the harness to `Scripts/run-tests.sh` with the fork sources it needs, and run the
      suite.

---

## Risks and how this plan handles them

| Risk | Handling |
|---|---|
| A prompt starting with `-` read as a CLI flag | 2.1 puts `--` before the prompt argument, so the first message stays verbatim and first. 2.2 checks once, by hand, that both CLIs accept `--`. The tests in 7.1 cover it. |
| A very long chat passing argv limits | Overflow file at 32 KB (2.1) |
| The terminal's `PATH` picks another `claude` (Homebrew 2.1.287 vs `~/.local/bin` 2.1.296) | 2.2 passes the absolute path Tinycast resolves |
| One chat leaking into the next | A new root for each chat. Claiming checks that the root is `ready`, never `inUse` |
| An always-on server costs something | Measured as negligible. The toggle defaults to off |
| Upstream merge conflicts | Small hooks, a fork-owned folder, audit rows (Group 5) |
