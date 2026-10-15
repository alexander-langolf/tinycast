## Context

File search today is two engines behind one session.

- **Spotlight.** `FileSearchService` runs `MDQuery` over resolved scopes, capped at 1,000 candidates. It
  stats each path and ranks with `FileSearchQuery.rank`. It also serves the blank-screen Recently Used
  list.
- **ripgrep home index.** `ForkRipgrepIndex` holds `rg --files` output for home in memory. It refreshes
  every two minutes. `ForkRipgrepQuery` scores whole paths with `ForkFzf`. `ForkFileSearchService`
  merges provisional Spotlight rows with the indexed answer.

`FileSearchSession` debounces, cancels and publishes. Search Files and File Navigator global (word)
search share the one `ForkRipgrepIndex` that `AppCore` owns.

`fsearch` (`~/.local/bin/fsearch`) is a separate local tool with a daemon, a persistent on-disk index and
a file watcher. Probed on this machine:

- `fsearch stdio` reads JSON lines `{"q": "...", "id": N}` and writes
  `{"hits":[{"path","kind":"file|dir","mtime","size","score"}], "id", "ok", "took_us"}`. `id` is echoed.
  A warm query takes 2-3 ms in the daemon.
- The index holds about 6.4M entries and `full_disk_access` is `false`.
- Inline filters are part of the query string (`*.md`, `src/`, `!build/`, `git:modified`). Results come
  back best first, with a default of 50 hits for common queries.

## Goals / Non-Goals

**Goals:**
- One candidate engine and one ranking authority for Search Files and navigator global search.
- Delete the Spotlight candidate path, the ripgrep index and its refresh lifecycle, and the engine setting.
- Keep the user-visible contract: the type filter, 120 ms typing debounce, 200-row cap, ignore patterns
  and scopes, the application-bundle exclusion, and stale-result safety.
- Fail visibly. A missing or dead `fsearch` shows "File search is unavailable".

**Non-Goals:**
- Content search, even though fsearch indexes content.
- Changing the navigator's direct folder listing or its ⌘F subtree scanner.
- Changing launcher, clipboard, snippet or navigator in-folder name matching, which keep `ForkSearch` /
  `ForkFzf`.
- Bundling or installing `fsearch` from Tinycast.

## Decisions

### 1. One `FSearchClient` owns a long-lived `fsearch stdio` child
`FSearchClient` lives in `Tinycast/Features/FileSearch/Service/`. It launches the child lazily on the
first nonblank query and writes one request per query with a monotonically increasing `id`. A single
off-main reader parses response lines and resumes the matching continuation. The process is terminated
on app exit and relaunched once, on demand, if it dies mid-session.

*Alternatives.* (a) Spawning `fsearch <query> --json` per keystroke. It is simpler, but pays process
startup and CLI-to-daemon connect on every query, and gives no clean cancel. (b) Talking to the daemon
socket directly. It is not a documented interface, so it would couple Tinycast to internals.
(c) `fsearch mcp`. It is meant for agents and adds a protocol layer for no gain.

### 2. fsearch owns ranking; Tinycast keeps only structural drops and the cap
Hits arrive ordered by `score`. The session keeps that order and applies, in this sequence: application
bundles dropped, hidden path components dropped (unless `Search hidden files` is on), ignore-list
exclusions, the type filter, then `prefix(200)`. `FileSearchQuery.rank`, `ForkRipgrepQuery` and the
Spotlight expression builders are deleted. `ForkSearch.terms` stays for syntax parsing only where other
features use it.

The extended term syntax (`'exact`, `^prefix`, `suffix$`, `!negation`) is passed to fsearch as typed. The
spec states it as "fsearch's query syntax" rather than restating its grammar, since fsearch owns it.

*Trade-off.* Ranking changes. fsearch's scorer replaces the fzf path scheme documented in
`ripgrep-search.md`, and ties and dot-folder behavior will differ. We accept that, because a second
ranking pass over fsearch's output would reproduce the duplication this change removes.

### 3. Push what fsearch can express; post-filter the rest
Scopes become path-prefix filters and the type filter becomes `kind:`/extension filters. Ignore
patterns that fsearch can express (`!node_modules/`, `!*.tmp`) are pushed as negations. Path globs it
cannot express stay in `FileSearchIgnoreList` as a local post-filter. Because post-filtering can leave
fewer than 200 rows, the client over-fetches (`limit` of 400) and the session re-queries with a larger
limit once if a full page filters down below 200. The exact filter spellings and the `limit` field are
verified against the installed binary in task 1.1 before any code depends on them.

### 4. Settings and scopes
`fileSearchScopes`, `fileSearchIgnorePatterns` and `Search hidden files` stay. `fileSearchEngine`
(`forkFileSearchEngine`) and the settings.json key `fileNavigator.searchEngine` are removed.
`SettingsFileSchema` has an exhaustive switch, so the build forces the binding to go. A stale stored
engine value is simply never read, with no migration code, per the "no compatibility layers" posture.

### 5. Availability instead of fallback
Discovery checks `~/.local/bin/fsearch`, then `PATH`, without a shell, as the ripgrep discovery does
today. If it is absent, or the child cannot start or exits non-zero, `FileSearchSession.State` becomes
`.failed` and the screen says "File search is unavailable". There is no Spotlight fallback. A silent
second engine is what produced the provisional-row merging, and the user chose to replace the
implementation.

### 6. Concurrency and cancellation
The client is `@MainActor` for state and does the pipe read on one off-main reader, matching
`ForkRipgrepProcess`'s documented shape. Each request returns through a `CheckedContinuation` keyed by
`id`. Superseding a query drops its continuation's result at the session's existing
revision/request check. Writing a newer request is the only cancellation fsearch needs, since it answers
in milliseconds. `FileSearchSession` keeps its injectable `SearchOperation`, so the harnesses still run
without a child.

### 7. Third-party dependency exception
`AGENTS.md` says zero third-party dependencies. This is an external, user-installed executable, not a
linked or bundled library. It is the same category as the `rg` dependency it replaces, and `fork.md`
records it. Nothing is vendored.

### 8. Recents stay on Spotlight for now (see Open Questions)
The blank screen keeps its two sorted Spotlight queries, so `FileSearchService` shrinks to the recents
path and its scope resolution. If fsearch can sort by `mtime`, a follow-up removes the last `MDQuery`.

## Probe findings (task 1.1)

Verified against the installed binary on 2026-10-13:

- Request `{"q","id","limit"}`: `limit` works (5 and 400 honored). `sort` is ignored, so there is no
  `mtime` sort and recents stay on Spotlight.
- Errors: `{"ok":false,"error":"..."}` with no `id` for non-JSON input, and with `id` for an unknown
  `type:` value.
- `type:` accepts `image`, `audio`, `video`, `doc`, `archive`. There is no folder type, and `kind:dir`
  is read as plain text. Hits carry `kind` (`file`/`dir`), so Folders is a local filter on `kind`.
- `*.ext`, `ext:` and `!term` negations work. A bare path fragment such as `github/tinycast/Tinycast/` or
  an absolute path acts as a fuzzy term, not an anchored prefix. A `~/` path matches nothing.
- fsearch does not exclude build output, `node_modules`, caches or dot-folders. Hidden components, the
  ignore list and the scope prefix must therefore be enforced locally, so over-fetching matters.
- Scopes: pushing the root path as a term reorders results (a fuzzy path word put an `xcuserdata` folder
  ahead of `~/github/tinycast` for `tinycast`), so scopes are enforced locally by prefix and nothing is pushed.

## Risks / Trade-offs

- **fsearch is not installed or its daemon is down** → "File search is unavailable" inline, and the
  client relaunches the child once per query batch. The pane in Settings shows the discovered path.
- **fsearch has no Full Disk Access today** (`full_disk_access: false`) → coverage can be thinner than
  Spotlight's. The Settings pane shows `fsearch status`'s flag and says which binary needs the grant.
- **Ranking regression** against the tuned fzf path scheme → capture a fixed set of representative
  queries before deletion (task 1.2) and compare top-5 results by hand. Accept differences only
  consciously.
- **Post-filter shortfall** → over-fetch plus one bounded re-query. Worst case is a short list, never a
  wrong one.
- **Index staleness** → fsearch's watcher owns freshness. A file created seconds ago may be missing, and
  there is no Tinycast-side refresh to lean on any more.
- **Hidden dependency drift** (fsearch protocol changes) → one client file and one fake-child harness
  isolate the contract. A response line that fails to decode fails the request, not the app.

## Migration Plan

1. Land the client and session wiring behind the existing seam, with the old engines still present.
2. Switch the production `FileSearchSession` and navigator global search to the client.
3. Delete the ripgrep index, query, process and service files, the engine enum and its setting.
4. Update tests, `run-tests.sh`, docs and the `search` spec.

Rollback is a `git revert` of step 2. Steps 1 and 3 are separate commits so that revert stays clean.

## Open Questions

- Should the blank-screen Recently Used list move to fsearch? Not today: fsearch has no `mtime` sort.
- Should Tinycast offer to run `fsearch install --login` when the daemon is missing, or only report the
  state?
