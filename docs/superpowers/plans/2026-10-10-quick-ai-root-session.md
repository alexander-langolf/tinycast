# Quick AI Root Session (Codex): implementation plan

> **For agentic workers:** work group by group. Codex implements each group from its brief and runs no
> builds, tests, formatters or commits. Claude builds, runs `Scripts/lint.sh` and
> `Scripts/fork-audit.sh`, relaunches Dev and commits between groups. Checkboxes (`- [ ]`) track
> progress. This is a **fork** feature, so read `docs/fork.md` first. Fork code lives in
> `Tinycast/Fork/QuickAIRoot/`. Upstream files get only `// FORK: quick-ai-root` hooks, each with a
> `docs/fork.md` row. **No tests until Sasha has verified the behaviour (Group 7).** Work on branch
> `al/quick-ai-root` and merge into `main` after verification. No worktrees. Never send synthetic
> input; visual checks use `screencapture -l` of Dev windows only.

**Goal and behaviour:** see `docs/features/quick-ai-root-session.md`, which is the spec. That doc
wins if this plan disagrees with it.

**Architecture in one line:** a fork-owned `ForkQuickAIRoot` keeps one persistent, read-only root
thread ready on the running Codex app-server. `CodexTurnRunner.prepareThread` claims it for Quick AI
sends. Start Work opens a terminal instance running `codex fork <root>` and retires the root. A JSONL
log and a retention prune clean up.

**Verified anchors** (`main` @ `6161df5d`):

| What | Where |
|---|---|
| Thread creation | `CodexTurnRunner.prepareThread`, `Tinycast/Features/AI/Service/CodexTurnRunner.swift:331` (`thread/start` with `ephemeral: true` at `:345-355`) |
| Idle shutdown | `ChatGPTSubscriptionManager.scheduleIdleShutdown`, `…/ChatGPTSubscriptionManager.swift:136` (600 s, `:9`) |
| Quick AI state | `AIChatSurfacesState.quickAI`, `…/AI/UI/AIChatSurfacesState.swift:9` |
| Quick AI show / new chat | `QuickAICoordinator.show` `:26`, `startNewChat` `:96` |
| Quick AI action menu | `AIScreen.actions(at:)`, `…/AI/UI/AIScreen.swift:22` |
| Shortcut map | `PaletteShortcut.resolve`, `Tinycast/Palette/PaletteShortcut.swift:~58-82`. **⇧⌘↵ is already `copyCalculation`**, handled by the Return handler; check the AI-mode branch before taking it. |
| Terminal launch | `TerminalInstancesCoordinator.open(command:directory:)`, `…/TerminalInstances/UI/TerminalInstancesCoordinator.swift:45` |
| Working folder | `ForkAIWorkingDirectory.url` (`docs/features/ai-working-directory.md`) |

---

## Group 0: Spike (Claude, no product code)

Answers the spec's four open questions. Scratch scripts only, in the session scratchpad. One trivial
real prompt is allowed.

- [ ] **0.1 Fork from the CLI.** Start a real app-server with Quick AI's flags, run `thread/start`
      with `ephemeral: false` and one trivial `turn/start`, then wait for `turn/completed`. Run
      `codex fork <threadId> 'say ok'` in a PTY, and record whether the fork carries the history and
      whether the rollout was on disk at `turn/completed`.
- [ ] **0.2 Instruction carry-over.** In that fork, ask "may you run shell commands here?" and record
      whether Tinycast's text-only developer instructions came with it.
- [ ] **0.3 `thread/delete`.** List the `~/.codex/sessions` files for a test thread before and after
      `thread/delete`.
- [ ] **0.4 Idle cost.** With Tinycast's MCP tool servers armed, leave the app-server idle for 15 min
      and record its RSS, its child processes and any network traffic (`nettop -p`).
- [ ] **0.5 Decide and record.** Choose the handoff path:
      - **A:** `codex fork <root> '<handoff>'` (spec default);
      - **B:** app-server `thread/fork` with new `developerInstructions`, then `codex resume <fork>`.

      Write the result into the spec ("Spike first" section → "Spike results"). Also settle the
      shortcut: ⇧⌘↵ if the AI screen's Return handler doesn't route it to the calculator, otherwise
      ⌥⌘↵.

**Gate:** Group 4 doesn't start until 0.5 has picked a path. A fork that refuses or loses the history
in both A and B stops the plan; report back to Sasha.

## Group 1: Settings and the log

- [ ] **1.1** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIRootSettings.swift`, holding `isEnabled`
      (default false) and `retention` (`.hour`, `.day` = default, `.week`). It's stored through the
      fork's settings pattern.
- [ ] **1.2** Add hooks so both values reach `AppSettingsKey`, `SettingsFileKey`/schema,
      `SettingsBackup`/coverage and `ForkSettingsSearch`, mirroring how the appearance tokens were
      wired (`// FORK: quick-ai-root`).
- [ ] **1.3** In the Quick AI section of `AISettingsView` (`Tinycast/Features/AI/Settings/AISettingsView.swift:~143`),
      add a one-line hook to a fork-owned `ForkQuickAIRootSettingsRows` holding the toggle "Keep a
      warm root session (Codex, experimental)" and the "Forget root sessions after" picker. When the
      provider isn't Codex, the toggle is disabled with a note saying why.
- [ ] **1.4** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIRootLog.swift`: an append-only JSONL at
      `<Application Support>/QuickAIRoot/log.jsonl` with events `warmed | claimed | retired |
      handedOff | deleted | fellBack`. Fields: `at`, `event`, `root`, optional `chat`, `terminal`,
      `reason`. A pure `prune(lines:olderThan:)` returns what to keep and which root ids have expired.
      It never writes message text.

**Done when:** the settings appear, round-trip through `settings.json` and backups, and search finds
them. `log.jsonl` is written only while the toggle is on.

## Group 2: Root state and claiming

- [ ] **2.1** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIRoot.swift`:
      - an `@MainActor` state machine with states `off`, `warming`, `ready(Root)`, `inUse(Root, chat:)`
        and `unavailable(reason)`;
      - `Root` = `threadID`, `model`, `webSearch`, `instructions` and `startedAt`;
      - a pure reducer plus effects: start a thread, retire, log. `CodexTurnRunner` owns the client,
        so the effects run through a small closure it supplies (`startThread(params) async throws
        -> String`).
- [ ] **2.2** Hook `CodexTurnRunner.prepareThread` (`:331`) behind `// FORK: quick-ai-root`. When the
      request is from Quick AI and the root is `ready` with matching model, web search and
      instructions, use its `threadID` and skip `thread/start` and `inject_items`. Otherwise, today's
      path runs unchanged. A mismatch retires the root and logs `retired(reason: mismatch)`.
- [ ] **2.3** Identify the surface with the less invasive of two options, as decided in 0.5:
      - an optional `surface` on `AIRequest`, set by `AIChatState` when it's `chats.quickAI`;
      - a fork-owned registry that maps conversation ids to Quick AI.

      Record the choice in `docs/fork.md`.
- [ ] **2.4** The root is the only thread created with `ephemeral: false`. Every other thread keeps
      `ephemeral: true`.

**Done when:** with the toggle on, a Quick AI send after warming shows in the debug log as `claimed`
and makes no `thread/start` request. With the toggle off, behaviour is byte-for-byte today's.

## Group 3: Keep-alive, prewarm, retire

- [ ] **3.1** Hook `ChatGPTSubscriptionManager.scheduleIdleShutdown` (`:136`): while
      `ForkQuickAIRoot.isEnabled`, don't schedule the shutdown. Turning the toggle off re-arms it.
- [ ] **3.2** Hook `QuickAICoordinator.show` (`:26`): if the root is enabled and not `ready`/`inUse`,
      start warming in the background so showing the palette is never blocked.
- [ ] **3.3** Hook `QuickAICoordinator.startNewChat` (`:96`), and the open-policy `.startNew` path at
      `:84`: retire the current root (`retired(reason: newChat)`) and warm the next one.
- [ ] **3.4** App-server exit or relaunch (`CodexAppServerClient.onExit` / `onRelaunch`): the root
      goes `unavailable` and the current chat falls back to ephemeral (`fellBack`). The next `show`
      warms again.

**Done when:** spec acceptance criteria 1, 2, 3, 7 and 8 pass by hand.

## Group 4: Start Work

- [ ] **4.1** Create `Tinycast/Fork/QuickAIRoot/ForkQuickAIHandoff.swift`. It builds the command for
      path A or B (from 0.5), with every argument single-quoted for zsh and the spec's fixed handoff
      prompt. A pure `command(rootID:)` returns the string.
- [ ] **4.2** Hook `AIScreen.actions(at:)` (`:22`) to add "Start Work in Codex" (systemImage
      `hammer`, the shortcut from 0.5). It's shown only when the root is `inUse`, the chat has at
      least one completed assistant turn, and nothing is streaming.
- [ ] **4.3** Add the shortcut through the same route `continueInChat` uses: one new
      `PaletteShortcut` case plus `resolve`, or the AI screen's own key handler if that's less
      invasive.
- [ ] **4.4** The action:
      1. calls `TerminalInstancesCoordinator.open(command:directory:)` with the working folder, or
         home when none is set;
      2. logs `handedOff(terminal:)`;
      3. retires the root;
      4. starts a new Quick AI chat.

**Done when:** spec acceptance criteria 4 and 5 pass by hand. The Codex TUI in the instance shows the
conversation, asks before it runs a shell command, and Quick AI is empty afterwards.

## Group 5: Retention

- [ ] **5.1** When a root is retired and once an hour while the app-server runs, read the log and
      `thread/delete` each retired root older than the retention. Skip any root that is `inUse`. Log
      `deleted`, then rewrite the log without expired lines (atomic replace).
- [ ] **5.2** A `thread/delete` failure is logged and retried on the next prune. It never surfaces in
      the UI.

**Done when:** spec acceptance criterion 6 passes with retention set to 1 h. The test can temporarily
use a Debug-only override of 2 min, which is removed before the merge.

## Group 6: Docs

- [ ] **6.1** Add a `docs/fork.md` row for every `// FORK: quick-ai-root` hook, and make
      `Scripts/fork-audit.sh` pass.
- [ ] **6.2** In `docs/features/quick-ai-root-session.md`, set the status to "built, experimental",
      add the spike results, and list each acceptance criterion with its result.
- [ ] **6.3** Add a short cross-reference from `docs/features/ai.md` (Quick AI section) to the new doc.
- [ ] **6.4** In the vault's `Tinycast.md` feature row, change "spec only" to its new state.

## Group 7: Sasha verifies

- [ ] **7.1** Sasha runs acceptance criteria 1–8 on Dev, with the toggle on and then off.
- [ ] **7.2** Measure the real time to first token, warm and cold, 5 runs each, and record it in the
      spec.
- [ ] **7.3** Merge `al/quick-ai-root` into `main` (merge, never rebase). Pushing needs Sasha's go-ahead.

## Group 8: Tests (only after 7.1)

- [ ] **8.1** `Tests/quick-ai-root-test.swift`, covering:
      - reducer transitions, including mismatch, crash fallback and retire-while-in-use;
      - log pruning;
      - handoff command quoting (single quotes, newlines, a non-ASCII prompt).
- [ ] **8.2** Add the harness to `Scripts/run-tests.sh` with the fork sources it needs, and run the
      suite.

---

## Risks and how this plan handles them

| Risk | Handling |
|---|---|
| A fork keeps the text-only instructions and won't work | 0.2 detects it, and path B swaps the instructions |
| One chat leaking into the next | A new root per chat. Claiming checks the root's state is `ready`, never `inUse` |
| An always-on server costs something | 0.4 measures it. The toggle defaults to off |
| Shortcut clash with ⇧⌘↵ | Settled in 0.5 |
| Upstream merge conflicts | Small hooks, fork-owned folder, audit rows (Group 6) |
