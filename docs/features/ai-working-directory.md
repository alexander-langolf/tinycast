# AI working directory

A fork setting: the folder Quick AI and AI Chat start their installed agents in, so Claude Code and
Codex load that folder's `CLAUDE.md` or `AGENTS.md` as they would in a terminal. Set it in
**Settings → AI → Chat → Working folder**. Unset, every route behaves exactly as upstream.

## Invariants

- **Two folders, never one.** The *working directory* is only ever a process's cwd or a CLI's
  directory flag. The *scratch directory* (`<Application Support>/InstalledAI/Workspace`, and
  `InstalledAI/Codex/Workspace` for Codex) keeps every file Tinycast writes: Grok's prompt file,
  Claude's MCP configuration, the `0700` folder itself, and the launch-time sweep of stale turn files.
  No Tinycast code creates, writes or deletes anything in the working directory.
- **Unset or missing falls back to scratch.** `ForkAIWorkingDirectory.url` returns nil unless the
  path is absolute or `~/` and is a folder at the moment it is read; the fallback is logged once per
  path under `com.tinycast` / `AIWorkingDirectory`.
- **Tools stay off.** The routes keep their safety prompts, `--tools ""`, `--deny *`, deny-all
  OpenCode permissions, Cursor's ask mode and Codex's read-only sandbox. Only the starting folder moves.
- **Probes stay in scratch.** Version, sign-in and model-list probes, and Claude's title request,
  never need a project, so they never run in the working directory.

## Where it applies

| Route | Working directory reaches it as |
| --- | --- |
| Claude Code | process cwd |
| OpenCode | process cwd and `--dir`; also the cwd of `session delete` |
| Grok | process cwd and `--cwd`; also the cwd of `sessions delete` |
| Cursor | process cwd and `--workspace` |
| Codex | app-server process cwd, `mcp list` cwd and `thread/start`'s `cwd` |

Claude and the per-turn CLIs read the setting at each turn. Codex reads it when its app-server
launches; a change stops and re-checks a running server, which ends any turn in flight.

## Persistence

`ForkAIWorkingDirectory.path` is stored under the `aiWorkingDirectory` defaults key, `~`-relative
where it can be, and mirrored as `ai.workingDirectory` in settings.json with the same folder rule as
`notes.folder`. Backups leave it out: it names a folder on this Mac, and an import must not hand that
folder's instructions to its agents.

## Behaviour of the CLIs in that folder

- Claude Code also applies the folder's `.claude/settings.local.json`, including its `env`.
- Codex also applies a trusted project's `.codex/config.toml`; Tinycast's per-thread `sandbox` and
  `approvalPolicy` still win over it.
- Cursor's ask mode can read files in its workspace, which is now that folder.
