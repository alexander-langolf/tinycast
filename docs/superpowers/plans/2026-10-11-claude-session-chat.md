# Claude Session Chat: implementation plan

> **For agentic workers:** work group by group. Codex implements each group from its brief and runs no
> builds, tests, formatters or commits. Claude builds, runs `Scripts/lint.sh` and
> `Scripts/fork-audit.sh`, relaunches Dev **with `CLAUDE*`/`ANTHROPIC*` stripped from the
> environment**, and commits between groups. This is a **fork** feature: read `docs/fork.md` first.
> Fork code lives in `Tinycast/Fork/ClaudeSession/`. Upstream files get only
> `// FORK: claude-session-chat` hooks, each with a `docs/fork.md` row. **No tests until Sasha has
> verified the behaviour (Group 6).** Branch `al/quick-ai-root`, the same branch as Start Work. No
> worktrees, no synthetic input into Sasha's apps, and never `claude -p` / `--print` / stream-json
> / the Agent SDK / `--attach-serve`.

**Goal and behaviour:** `docs/features/claude-session-chat.md`, the spec. It wins if this plan
disagrees.

**Architecture in one line:** ⌘↵ runs `claude --bg` with fork hooks and the handoff prompt, then
moves the chat to the AI Chat window. There, a fork-owned `AIProvider` sends each message through a
hidden `claude attach` PTY, and builds the reply from hook events plus the transcript JSONL.

**Verified anchors** (`al/quick-ai-root` @ `0675d412`):

| What | Where |
|---|---|
| Chat provider choice | `AIChatCoordinator.provider(for:scopedTo:)`, `Tinycast/Features/AI/UI/AIChatCoordinator.swift:328` |
| Model picker | `AIChatDetailView.swift:209` (`AIModelPicker`, `:437`) |
| Quick AI → window | `QuickAICoordinator.continueInChat()` `:142` / `continueInChat(id:)` `:127` |
| Chat deletion | `AIChatSurfacesState.delete(id:)` `:110`, `deleteAll()` `:116`; `ChatHistoryScreen.delete(at:)` `:49` |
| Stream events | `AIStreamEvent`, `Tinycast/Features/AI/Model/AIRequest.swift:144` (`text`, `thinking`, `toolCall`, `toolResult`, `finished`) |
| PTY | `TerminalProcess`, `Tinycast/Features/TerminalInstances/Service/TerminalProcess.swift:6` |
| Start Work today | `ForkQuickAIHandoffCoordinator.launch(...)`, `Tinycast/Fork/QuickAIRoot/ForkQuickAIHandoffCoordinator.swift` |
| Claude executable | `ExecutableLocator.locate("claude", extraHomePaths:)`, or the Settings override (as in `ForkQuickAIRootSettingsRows`) |

---

## Group 0: Spike the four open questions (Claude, no product code)

Scratch scripts in the session scratchpad, with the environment stripped and trivial prompts. Test
sessions are stopped and removed afterwards.

- [x] **0.1** Two `claude attach` clients on one session: do both see output, can both type, or does
      the second take over? This decides whether the writer must detach while Attach is open.
- [x] **0.2** Hook stdin: one JSON line per event or not (sample every event type, including a long
      prompt with newlines). This decides between a `cat >>` hook command and a fork-owned helper.
- [x] **0.3** `claude --bg --resume <session id>` on a stopped session: same id, or a copy?
- [x] **0.4** `<pasted_content>` wrapping: at what size or speed it happens, and its exact form, for
      delivery matching.

Record the answers in the spec's "Spike first" section. **Done 2026-10-11:** two clients share the session; stdin is one JSON line (`cat >>`); resume continues the same id; the wrapper form is recorded. **Gate:** if 0.1 shows that two clients
corrupt the session, Group 3's Attach closes the hidden writer before it opens the terminal. That
changes the design but doesn't stop it.

## Group 1: Host, registry, hooks

**Done 2026-10-11** (build, lint and fork audit green). Runtime check: Dev writes `hooks.json` at
launch, and a `--bg` session started with it filled `events.jsonl` with SessionStart,
UserPromptSubmit and Stop, each carrying `session_id` and `transcript_path`. The registry write is
exercised for real when Group 3 starts sessions from Start Work. Findings fixed in review: `resume`
now runs in the session's folder; Claude's stderr is the error message; the agents listing skips
interactive sessions, which have no short `id`. `--bg` refuses an untrusted folder (see the spec).
The implementation uses one shared `ClaudeSessions/events.jsonl`, filtered by payload `session_id`,
as documented in the spec. The temporary Debug scratch hook is `AppCore.debugStartClaudeSession`,
in `Tinycast/Fork/ClaudeSession/ForkClaudeSessionDebug.swift`; remove it before merge.

- [x] **1.1** `ForkClaudeSessionHost`:
      - `start(prompt:directory:) async throws -> Handle`, which runs
        `claude --bg --settings <hooks> -- <prompt>` with the clean environment (strip `CLAUDE*`,
        `CLAUDECODE`, `ANTHROPIC*`) and parses `backgrounded · <id>`;
      - `lookup(id)` through `claude agents --json --all`, giving `sessionId`, `status`, `state` and
        `cwd`;
      - `stop(id)` and `resume(sessionID)`.
- [x] **1.2** The hooks file at `<Application Support>/ClaudeSessions/hooks.json`, written at launch,
      for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse` (matcher `*`),
      `PermissionRequest`, `Notification` and `Stop`. The command appends stdin to
      the shared `ClaudeSessions/events.jsonl`; readers select the session id from the hook's own
      payload, as documented in the authoritative spec.
- [x] **1.3** `ForkClaudeSessionRegistry`: `ClaudeSessions/registry.json`, mapping chat id to short
      id, session id, transcript path, folder and read offset. Atomic writes; no message text.

**Done when:** a scratch call from the Debug-only fork hook (removed before the merge) starts a
session, the events file fills in, and the registry holds the entry.

## Group 2: Reader, writer, provider

**Built 2026-10-11** (build, lint, fork audit green). A scratch PTY probe confirmed the writer's
assumptions on a live session: `claude attach` turns on bracketed paste in 0.16 s, a 3-line paste
with quotes, `$HOME`, `!!` and unicode arrives exactly (`UserPromptSubmit` 0.05 s after Return), and
final assistant lines carry `stop_reason: end_turn`. Acceptance criteria 2, 3 and 6 run in the chat
UI once Group 3's Start Work creates session chats. Sessions start and resume with
`--dangerously-skip-permissions`.

- [x] **2.1** `ForkClaudeSessionReader`:
      - watches the events file (`DispatchSource` on the file) and tails the transcript from the
        saved offset;
      - maps lines to `AIStreamEvent` per the spec;
      - ends the turn on `Stop` plus the final assistant message, waiting at most 2 s;
      - passes on turns it didn't send as `foreignTurn(user:assistant:)`, for 2.4.
- [x] **2.2** `ForkClaudeSessionWriter`:
      - a hidden `TerminalProcess` running `claude attach <id>` (clean environment), started on
        demand and dropped after 10 minutes idle;
      - `send(text) async -> Delivery`: waits for the guard (between turns, no approval waiting, no
        Attach open), sends a bracketed paste then Return after 300 ms, and confirms on
        `UserPromptSubmit` within 5 s (ignoring the `<pasted_content>` form from 0.4);
      - never retypes on its own.
- [x] **2.3** `ForkClaudeSessionProvider: AIProvider`: `stream(request)` sends the request's last
      user message and yields the reader's events until the turn ends. "Not delivered" ends the reply
      with an error and Retry.
- [x] **2.4** Hook `AIChatCoordinator.provider(for:scopedTo:)` (`:328`): a registered chat returns
      the session provider. Foreign turns (2.1) are appended to that chat as messages.

**Done when:** acceptance criteria 2, 3 and 6 pass on a session started from the Group 1 Debug
item.

## Group 3: Start Work, approvals, Attach, chat UI

**Built 2026-10-11** (build, lint, fork audit green); acceptance criteria 1 and 4 await Sasha in Dev. Start Work registers the background session and moves the
chat into AI Chat, with the initial reply owned by the chat rather than resubmitted. Approval
notices offer Attach; the terminal pauses the writer until it closes or exits. Session chats have
a folder label, End Session makes the composer read-only, and Resume updates the registry.
The task boxes remain unticked pending verification.

- [x] **3.1** In `ForkQuickAIHandoffCoordinator`, ⌘↵ with Claude: build the handoff prompt as today,
      call `host.start`, register the chat, move it to the window (`continueInChat`), stream the
      first reply, and start a new Quick AI chat. ⌃⌘↵ (Codex) is unchanged.
- [x] **3.2** Approvals: `PermissionRequest` → a row "Claude needs approval: <tool>" with Attach,
      plus a badge on the chat. It clears on `PostToolUse` or `Stop`. `Notification`
      (`permission_prompt`) is the fallback.
- [x] **3.3** Attach and Open in Terminal: a terminal instance running `claude attach <id>`, titled
      "Claude Code · <folder>". The writer pauses (or detaches, per 0.1) while it's open.
- [x] **3.4** Hook `AIChatDetailView` (`:209`): a registered chat shows "Claude Code session ·
      <folder>" in place of `AIModelPicker`.
- [x] **3.5** Hook the chat action menu: Open in Terminal, End Session (`host.stop`, then the chat
      goes read-only), and Resume when it has ended.

**Done when:** acceptance criteria 1 and 4 pass.

## Group 4: Lifecycle

**Built 2026-10-11** (build, lint, fork audit green); acceptance criteria 5, 7 and 8 await Sasha. A stopped session is listed without `status`, which counts as ended. Launch reconciliation lists sessions once through the host,
reuses `provider(chatID:)` for live readers at their saved offsets, and persists ended state for
stopped or missing sessions. Reconciliation's registry IO, CLI commands and listing decoding run off-main;
the coordinator owns and cancels the deferred launch task, and failures only log. Group 3 already
implements 4.2: Resume runs in the saved folder, replaces the registry metadata, clears ended state
and reconnects, retaining the offset when the transcript path is unchanged.

Deletion is intercepted at `AIChatSurfacesState` for both surfaces; `ChatHistoryScreen` already
routes there through `QuickAICoordinator`. A Tinycast dialog offers Delete and Stop Session(s),
Delete Chat(s) Only, or Cancel. Only the first choice runs stop then remove before unregistering;
the second unregisters without stopping the daemon. Readers, writers and pending foreign-turn
callbacks are disconnected before history is removed. Bulk deletion snapshots its targets and
preserves pinned chats, including chats pinned while the dialog is open. Failed session cleanup
keeps that chat and its registration for retry. Build, lint, fork audit and runtime acceptance
criteria remain for Claude; no builds, tests, formatters, generators or git commands were run here.

- [x] **4.1** At launch, check the registry against `agents --json --all`: reconnect the reader for
      live sessions (from the saved offset) and mark gone ones "Session ended".
- [x] **4.2** Resume: `claude --bg --resume <session id>` (per 0.3), then update the registry.
- [x] **4.3** Hook `AIChatSurfacesState.delete(id:)` / `deleteAll()`: for a registered chat, ask
      whether to stop the session too. `claude rm` runs only on yes.

**Done when:** acceptance criteria 5, 7 and 8 pass.

## Group 5: Docs

- [x] **5.1** `docs/fork.md` rows for every `claude-session-chat` hook; `Scripts/fork-audit.sh`
      passes.
- [x] **5.2** Spec status set to "built, experimental", with each criterion and its result.
- [x] **5.3** `quick-ai-root-session.md`, Start Work section: ⌘↵ with Claude now opens a session
      chat; link to this spec.
- [x] **5.4** The vault's hub note: Phase 0a's host verdict is `--bg`, and this feature is its
      first use.

## Group 6: Sasha verifies

- [ ] **6.1** Acceptance criteria 1–9 on Dev.
- [ ] **6.2** Merge into `main` after Start Work's own verification. Pushing needs Sasha's go-ahead.

## Group 7: Tests (only after 6.1)

- [ ] **7.1** `Tests/claude-session-test.swift`, covering:
      - transcript-line → event mapping (from recorded spike transcripts);
      - turn-end timing (`Stop` before or after the final message);
      - delivery matching, with and without `<pasted_content>`;
      - the write guard;
      - registry round trip.
- [ ] **7.2** Add it to `Scripts/run-tests.sh`.

---

## Risks

| Risk | Handling |
|---|---|
| `claude --bg` / `attach` / `agents --json` change in a Claude Code update | One host type owns every CLI call. The registry check at launch shows "Session ended" rather than failing |
| Two writers (chat and Sasha in the terminal) type at once | The write guard, plus pausing or detaching while Attach is open (0.1) |
| A missed hook or a reordered event | The reader also polls the transcript every 0.5 s during a turn, and turn end needs both `Stop` and the final message |
| A message typed while Claude waits for approval lands in the approval prompt | The guard holds it until `PostToolUse` or `Stop` |
| Transcript format details (attachment, mode and title lines) | The reader ignores unknown types, and the tests use recorded transcripts |
