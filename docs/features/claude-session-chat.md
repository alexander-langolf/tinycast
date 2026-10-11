# Claude session chat: specification

**Status:** Group 1 (host, hooks, registry) built; Group 2 (reader, writer, provider and chat hook)
built; Groups 3–4 implemented, unverified; Group 5 to do.
It's an experiment, and it extends Quick AI's Start Work
(`docs/features/quick-ai-root-session.md`). Evidence comes from the vault note *Tinycast Agent Hub —
Design & Plan*, section "Spike results: background Claude (2026-10-11)".

## Goal

⌘↵ in Quick AI starts a real interactive Claude Code session **in the background** and moves Sasha
to the AI Chat window. There, the conversation continues with that session: what he types goes
into the session, and the session's replies, tool steps and approval requests show up as chat
messages. The session is an ordinary `claude --bg` session. Claude's own daemon keeps it alive
through a Tinycast restart, and `claude attach <id>` opens it in any terminal.

```
 Quick AI ── ⌘↵ ──▶ claude --bg '<handoff prompt>'      (Claude's daemon hosts the TUI)
                       │ id
                       ▼
 AI Chat window ◀── hooks (events) + transcript JSONL (content) ── session
       │ send
       └──▶ hidden `claude attach <id>` PTY: paste + Return ──▶ session
       │ Attach
       └──▶ terminal instance running `claude attach <id>` (Sasha answers approvals there)
```

## Invariants

- **Interactive only.** The session is `claude --bg`, and input goes through `claude attach`. It
  never uses `claude -p`, `--print`, `--input-format`/`--output-format stream-json`, the Agent SDK
  or `--attach-serve`.
- **No approval prompts.** Sessions start (and resume) with `--dangerously-skip-permissions`
  (Sasha's choice, 2026-10-11; verified: Bash ran in `bypassPermissions` mode with no
  `PermissionRequest`). Anything that still asks (a `PermissionRequest` or an
  `AskUserQuestion`-style prompt) is shown with Attach. Tinycast never answers it, and it never
  sends keys other than the message Sasha sent.
- **One writer.** Tinycast types into the session only between turns, with no approval waiting, and
  only when no Attach terminal is open for that session. Anything sent at another time waits in a
  queue that the chat shows.
- **The session's environment is clean.** The launch strips inherited `CLAUDE*`, `CLAUDECODE` and
  `ANTHROPIC*` variables, so a Tinycast that was itself started from a Claude shell never turns the
  session into someone's child session.
- **The executable is the one Tinycast resolves for Claude** (`ExecutableLocator`, or the command
  override in Settings).
- **Off means upstream.** With "Start Work in" set to Off or Codex, nothing in this spec runs.

## Behaviour

### Start

⌘↵ in Quick AI, when "Start Work in" is Claude Code:

1. Builds the handoff prompt exactly as Start Work does today: the first message verbatim and first,
   then the exchange, then the closing line.
2. Runs, in the working folder and with the clean environment:

   ```sh
   claude --bg --dangerously-skip-permissions --settings '<fork hooks file>' -- '<handoff prompt>'
   ```

   It reads the short id from the output (`backgrounded · <id>`), then the session id and
   transcript path from `claude agents --json` or the first hook event.
   `claude --bg` refuses a folder Claude Code hasn't trusted yet ("Workspace not trusted. Run
   `claude` in <folder> once and accept the trust prompt"). Start Work then shows that message
   and falls back to today's visible terminal, where Sasha answers the trust prompt himself.
3. Moves the Quick AI chat into the AI Chat window (today's Continue in AI Chat path), registers
   `chat id → session` in the fork's registry, and shows the first reply arriving as the session
   produces it.
4. Quick AI starts a new chat.

⌃⌘↵ (Codex) keeps today's behaviour: a visible terminal instance.

### Reading the session

- **Events:** the fork's hooks file adds command hooks for `SessionStart`, `UserPromptSubmit`,
  `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification` and `Stop`. Each appends its JSON
  line to `<Application Support>/<Tinycast bundle id>/ClaudeSessions/events.jsonl` using
  `/bin/cat >> '<events file>'`. This is one shared file: readers filter each complete line by the
  payload's `session_id`, rather than parsing JSON in a shell to choose a filename. Paths containing
  quotes are shell-escaped in the hook command; Claude itself is launched directly as a `Process`.
  `--settings` merges with Sasha's own settings, so his hooks still run (seen in the spike).
  `SessionStart`'s `transcript_path` supplies the path when the agents listing doesn't include it.
  Hooks are written atomically at Tinycast launch and again before start/resume; the bundle-id root
  keeps Dev and installed builds separate.
- **Content:** the transcript JSONL, read from the last offset on every event, and every 0.5 s while
  a turn is running. Mapping:
  - assistant `text` → `.text`;
  - `thinking` → `.thinking`;
  - `tool_use` → `.toolCall(id, origin: "Claude Code", title: <tool name and short input>)`;
  - user `tool_result` → `.toolResult(id, isError:)`;
  - everything else (attachments, titles, mode lines) is skipped.
- **End of turn:** `Stop`, then the final assistant message, which reaches the transcript 0.1–0.9 s
  after `Stop`. The reader waits up to 2 s for it before it finishes the reply.
- **Turns the chat didn't send** (typed by Sasha in an Attach terminal) show up in the chat as
  ordinary user and assistant messages when the reader reaches them.
- Replies arrive a message at a time. There's no word-by-word streaming.

### Sending

- A message from the chat is pasted into a hidden PTY running `claude attach <id>`: a bracketed
  paste, then Return after 300 ms.
- **Delivery is confirmed** when `UserPromptSubmit` arrives with the same text, ignoring a
  `<pasted_content>` wrapper Claude Code may add. With no confirmation after 5 s, the message is
  marked "not delivered" with Retry, and it's never retyped automatically.
- The hidden attach PTY is started on demand and dropped after 10 minutes without use. Dropping it
  leaves the session running (seen in the spike).

### Approvals and Attach

- **`PermissionRequest`** (about 0.13 s after the tool is requested) shows a row "Claude needs
  approval: <tool>", with **Attach** in the reply and a badge on the chat. The `Notification` hook
  is only a fallback, because it waits about 6 s.
- **Attach** opens a terminal instance running `claude attach <id>`. The hidden writer pauses while
  it's open. The approval row clears when `PostToolUse` or `Stop` arrives.
- The chat's action menu also has **Open in Terminal** (the same Attach) and **End Session**
  (`claude stop <id>`; the transcript stays and the chat becomes read-only).

### Lifecycle

- **Closing the window or quitting Tinycast** leaves the session running. On launch, the registry is
  checked against `claude agents --json --all`, and live sessions are reconnected (reader from the
  saved offset, writer on demand).
- **A session that has stopped or gone:** the chat shows "Session ended", with **Resume**
  (`claude --bg --resume <session id>`) when the transcript still exists.
- **Deleting the chat** asks whether to stop the session too. It never runs `claude rm` without
  that answer.
- The registry is a fork-owned JSON file (`ClaudeSessions/registry.json`). It holds chat id, short
  id, session id, transcript path, working folder, read offset and an optional ended flag, and no message text: the chat
  history already holds that, as for any chat.

## Code layout

**Fork-owned**, in `Tinycast/Fork/ClaudeSession/`:
- `ForkClaudeSessionHost`: launch with a clean environment, parse the id, `agents --json`, stop,
  resume.
- `ForkClaudeSessionWriter`: the hidden attach PTY, the write guard, the queue, delivery
  confirmation. It reuses the terminal instances' `TerminalProcess`.
- `ForkClaudeSessionReader`: events file plus transcript tail → `AIStreamEvent`.
- `ForkClaudeSessionProvider: AIProvider`: one `stream(request)` per sent turn.
- `ForkClaudeSessionRegistry`: chat ↔ session, persisted.
- The hooks file and the hook command.

**Upstream hooks** (`// FORK: claude-session-chat`, each with a `docs/fork.md` row):

| File | Hook |
|---|---|
| `AIChatCoordinator.provider(for:)` | A registered chat gets `ForkClaudeSessionProvider`. |
| Chat window composer / model picker | A registered chat shows "Claude Code session · <folder>" instead of the model picker. |
| Chat action menu | Open in Terminal, End Session, Resume. |
| Chat deletion | Ask whether to stop the session. |
| `ForkQuickAIHandoffCoordinator` (fork-owned) | ⌘↵ with Claude takes the session path instead of the visible terminal. |

## Acceptance criteria

Group 1 has a temporary `#if DEBUG` scratch entry point in
`Tinycast/Fork/ClaudeSession/ForkClaudeSessionDebug.swift`, to remove before merge. From a Debug
session's Swift debugger, exercise it with an explicit prompt and working folder:

```swift
Task { @MainActor in
    do {
        let result = try await AppCore.shared.debugStartClaudeSession(
            prompt: "Reply with hello", directory: "/path/to/working/folder")
        AppCore.shared.showMessage(result)
    } catch {
        AppCore.shared.showMessage(error.localizedDescription, tone: .danger)
    }
}
```

It calls the host and registers a fresh scratch chat UUID after resolving the transcript path.
It does not create an AI Chat conversation or change Quick AI's Start Work routing. Inspect the
Dev channel's `ClaudeSessions/events.jsonl` and `registry.json` for Group 1's done criterion.
Session commands have a 30-second timeout; cancellation or timeout terminates only the CLI client,
not a daemon-hosted session that may already have started. A metadata/transcript failure reports
the short ID so that the scratch session can be inspected and stopped manually. The host exposes
`stop(id:)` and `remove(id:)`; the scratch hook never stops or removes a session automatically.

1. **Start:** `+stardust what was in joyce handoff?` and ⌘↵ in Quick AI opens the AI Chat window
   within 2 s. The reply arrives there, with the sigil resolved by the session's hook, and
   `claude agents` lists the session.
2. **Continue:** a follow-up typed in the chat reaches the session (confirmed delivery), and the
   answer shows in the chat.
3. **Long input:** a 40-line paste with unicode, quotes, `$HOME` and `!!` arrives intact.
4. **Approval:** a request that needs approval shows the approval row within 1 s. Attach opens the
   terminal on the prompt, answering it there continues the turn, and the chat shows the result.
5. **Restart:** quitting Tinycast mid-session and relaunching reconnects the chat, and the next
   message works.
6. **Typed in the terminal:** a message typed in an Attach terminal appears in the chat.
7. **End and resume:** End Session stops it, and the chat is read-only. Resume brings it back with
   its history.
8. **Clean environment:** with Tinycast started from a Claude shell, the session still saves its
   transcript and isn't a child session.
9. **Off:** with "Start Work in" set to Codex or Off, nothing in this spec runs.

## Spike first (Group 0 of the plan)

Verified on 2026-10-11 (Claude Code 2.1.296): `--bg` hosting, input through attach, live hooks, the
transcript filling in during a turn, `PermissionRequest` timing, the session surviving the client,
and `--settings` merging with the user's hooks. Group 0 answered the four open questions:

1. **Two `claude attach` clients share one session.** Both see all output, and either can type:
   a message typed in A showed in B, and the reverse. So Attach doesn't need to detach the hidden
   writer. The write guard still pauses it while an Attach terminal is open, so the two never type
   over each other.
2. **Hook stdin is one JSON line plus a trailing newline** (SessionStart, UserPromptSubmit, Stop;
   earlier runs parsed PreToolUse, PostToolUse, PermissionRequest and Notification the same way).
   The hook command can be a plain append: `cat >> '<events file>'`.
3. **`claude --bg --resume <session id>` on a stopped session continues it under the same short id
   and session id**, with its history. It doesn't start a copy.
4. **Claude Code wraps pastes from somewhere between 130 and 830 characters up** (one earlier
   2,843-character paste wasn't wrapped, so size isn't the only trigger). The form is:
   `\n\n<pasted_content id="caa1">\n` + text + `\n</pasted_content id="caa1">\n`. Delivery matching strips
   that wrapper when present. A short single-line message can be typed without a paste and arrives
   exactly. Multi-line text has to be pasted, because a typed newline would submit.

## Not in scope

- Word-by-word streaming (it would mean scraping the TUI).
- Answering approvals from Tinycast.
- Codex sessions in the chat (Codex keeps the visible terminal).
- Several sessions per chat, or switching a chat between sessions.
