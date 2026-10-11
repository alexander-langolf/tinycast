## Invariants

- Ripgrep owns candidate generation and whole-path ranking. `ForkSearch` parses terms and `ForkFzf`
  scores them; no Rust library, bundled executable, content search or on-disk index is added.
- AppCore owns one `ForkRipgrepIndex`. Both production file sessions use it through the existing
  `// FORK: search` seam. Injected harness operations and blank-query recents retain upstream behavior.
- The engine preference lives in Settings → File Navigator as **File search engine** and in
  `fileNavigator.searchEngine` in settings.json (`spotlight` / `ripgrep`). Unset chooses ripgrep when
  available, otherwise Spotlight. The experimental, machine-dependent choice stays out of backups.
- Discovery runs without a shell: `/opt/homebrew/bin/rg`, `/usr/local/bin/rg`, then PATH entries.
  Missing ripgrep uses Spotlight; the pane reports that fallback even if ripgrep is selected.
- Indexing starts on the first nonblank file search. After first use, palette opening refreshes an
  index older than two minutes. A refresh serves the old immutable snapshot, then swaps the whole
  array on the main actor. Changed engine/ignore settings invalidate it and cancel the old producer.
- Processes, pipe reads, NUL-delimited chunk parsing, exclusions and ranking run off-main. Owned
  cancellation terminates the child and waits on `ProcessExit`; app termination cancels the index.
  Query cancellation never cancels a shared index build needed by another session.
- Dot files and dot folders are included, independently of the navigator's direct-listing reveal
  toggle. Ignore patterns, home `Library/` and `.Trash/`, `.git/` and package descendants remain excluded
  recursively. Root access/package validation precedes subtree scanning.
- A ready home index replaces both Spotlight passes. Until it is ready, Search Files and navigator
  global words use the existing Spotlight path, then publish the indexed answer for the same request.
  Scopes outside home use Spotlight for the whole query. Recent files always use Spotlight.

## Candidate sources

The home command is `rg --files --hidden --no-messages --null --glob '!.git/'`, with cwd home,
anchored exclusions for `Library/` and `.Trash/`, and case-insensitive negative globs from compiled
defaults and safe user patterns. Name patterns and absolute patterns rooted inside home can prune
the home walk; subtree patterns are anchored relative to its scan directory, even though output paths
are absolute. Patterns whose glob semantics cannot safely be translated remain enforced by the original
`FileSearchIgnoreList` on absolute paths. The compiled six exclusions cannot be disabled.

Ripgrep's own ignore rules, including `.gitignore`, apply. Dot entries are included unless ignored;
`.git/` directories are explicitly pruned and symlinks are not followed. Home Library/cloud content and
external roots are absent from this index; select Spotlight to retrieve them. A manually configured
Library scope therefore stays excluded in ripgrep mode. Parent directories are derived from emitted files, deduplicated and marked with a trailing `/`
inside the index so folder filtering can run before the scoring cap. Empty directories have no source
file and are unavailable. Dot folders use the same parent derivation as other folders; a folder may
remain visible when only some children survive ignore rules. Directory markers are removed before
scoring or creating row values. Hidden metadata does not disqualify a ripgrep result.

The navigator's ⌘F scanner runs the same executable with its absolute folder argument, cwd that folder,
and `--max-depth 8`. Fixed home exclusions and safe absolute user patterns are translated relative
to the scan directory; root and row policy checks also reject excluded trees. Both this scanner and
the Swift fallback include dot entries, while enforcing ignore patterns and `.git/` independently of the reveal toggle. It streams
into the existing batch receiver, with 500 rows per batch and a cap of 50,000 emitted file/derived-directory
rows. Ripgrep does not expose visited-entry counts, so this cap counts visible candidates rather than every visited entry as the Swift walker does. Package ancestors
are checked with `DirectoryLister`, including package types beyond `.app` / `.pkg`. Direct listings
continue to use Swift and their existing hidden/ignored reveal behavior.
Subtree scanning emits a package ancestor once as an opaque file row and rejects its descendant rows;
rg can still enumerate those descendants internally. Empty packages, like empty directories, have no
emitted file from which to derive a row.

## Ranking

Ripgrep scores the complete home-relative path, without a `~/` prefix or a directory marker, using
fzf v2's path scheme. Every positive term must match that path; scores add across space-separated
AND terms. Negation, contiguous `'exact`, `^prefix` and `suffix$` keep their syntax and apply to the
same relative path. A slash needs no special case and may span parent directories and the filename.
Spotlight's fallback retains its separate filename/folder scoring and filename-only exclusions.

Slash boundaries earn 9 points, other word starts after `-`, `_` and `.` earn 8, and camelCase/digit
transitions earn 7. Matches earn 16 per character, the first boundary bonus doubles, consecutive runs
carry their boundary bonus, and gaps cost 3 initially plus 1 per additional character. Scores dominate
all tie breakers: filename matches have no absolute tier and folder scores have no 0.6 discount.
Equal scores prefer a match in the last path segment, then an earlier start within that segment,
shorter whole relative path, and incoming index. Equal-scoring alignments prefer the rightmost end,
as fzf's path scheme does. See [fzf's scorer](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go)
and [path tie breakers](https://github.com/junegunn/fzf/blob/master/src/result.go).

The retained dot-entry exception makes one leading filename dot neutral for an undotted,
unanchored term: the following character gets the slash boundary bonus and the filename start
ignores that dot. Explicit dotted terms and prefix anchors retain the literal spelling. Thus the home
`.config` folder remains first for `config`; unmodified fzf instead starts with `.aws/config`.
No fixed minimum-quality threshold drops weak matches. Low scores rank last, even when a weak
subsequence fills an otherwise empty shortlist. Rows fzf ranks highly must remain eligible.

An ASCII subsequence prefilter scans relative-path bytes case-insensitively; Unicode paths and terms
retain the existing case/diacritic folding. `ForkFzf.PathWorkspace` reuses a bounded score matrix and
tracks alignment starts without allocating highlighting positions. A contiguous slash-boundary run
can return its maximum possible score immediately. The current heap score can prune only alignments
whose proven upper bound cannot compete; it is not a quality cutoff.

A bounded worst-first heap initially retains 200 paths. Only competitive paths run scope/ignore
checks; retained paths fetch resource values and become rows. If missing metadata or a type filter
leaves fewer than 200 results from a full heap, the query repeats with the original 1,000-candidate
cap. This preserves the prior shortlist and metadata fallback behavior while tightening the bound
for broad queries. Folder markers filter before scoring. All Types and Folders read directory and
application flags together; only type-specific filters request content types. An unavailable content
type still admits a readable file under All Types. Application bundles remain excluded.

## Query and cancellation

The fork service owns each query task. New input cancels it immediately; cancellation propagates to
its detached scorer. Cancellation is checked at entry, every 128 index paths and each metadata read.
Publications validate the service revision and the upstream session's revision/query/filter. Removed
rows cannot reappear in a late batch. The upstream 120 ms debounce remains; query latency estimates
below exclude that debounce.

`ForkRipgrepProcess` has one off-main stdout reader. Its lock protects start/cancel and the child
lifecycle; the documented unchecked Sendable boundary never exposes the mutable parsing buffer to
another reader. Cancellation handlers are Sendable closures and only call that locked cancellation
method. There are no readability handlers or DispatchSource callbacks. The termination callback comes
from the existing nonisolated `Process.runObservingExit()` helper and signals its Sendable semaphore.
Navigator batch delivery is explicitly `@MainActor @Sendable`, and the receiver retains its existing
request/destination checks. Index publication tasks are main-actor isolated.

## Fallbacks and omissions

Missing or unlaunchable ripgrep and a failed first index build keep the Spotlight source. A failed
refresh retains its prior snapshot and logs the failure; the next palette opening can retry. Ripgrep
exit 1 is an empty listing. Exit 2 with emitted paths keeps those usable paths because unreadable
subdirectories commonly produce that status; exit 2 without paths and other exit statuses fail.
No content, diagnostics or permission grant is persisted. A failed subtree process clears any partial
rows and restarts the Swift walker; selecting Spotlight uses that walker directly. Cancellation never
starts a fallback. Spotlight's synchronous MDQuery work itself remains uninterruptible.

## Measurements and expectations

Sasha's Mac, 2026-10-11, `/opt/homebrew/bin/rg` 15.2.0:

| Command/source | Time | Files |
| --- | --- | --- |
| `rg --files`, cwd `~` | 3.5 s | 796k (564k under Library) |
| `rg --files -g '!Library/' -g '!.Trash/'`, cwd `~` | 0.83 s | 233k |
| `fzf --filter agentkit --scheme=path` over that list | 0.19 s | — |
| `rg --files`, cwd `~/work` | 0.69 s | 166k |

An implementation-session shell scan with `--null --no-messages` and anchored home exclusions took
0.708 s for 232,782 files, with 17,703,762 relative-path UTF-8 bytes (76.1 bytes/path), exit 2. It did
not run the app or Swift query implementation. Absolute prefixes add about 6.8 MB; String array
headers, allocations and derived directories suggest roughly **40–55 MB** for a settled snapshot.
The earlier refresh estimate was **80–120 MB of index-related peak memory**, before the app
baseline, including both snapshots and the directory set. These pre-hidden estimates no longer
describe the expanded index. The requested retained index therefore needs measurement against
the repository's usual 100 MB resident budget; it also intentionally survives palette closure.

A repeat on 2026-10-11 applied the actual six compiled defaults, package exclusions and fixed home
exclusions, with no additional user ignore patterns configured:

| Home scan | rg time | Emitted files | Indexed file/folder rows |
| --- | --- | --- | --- |
| Before: hidden entries omitted | 0.611 s | 136,767 | 158,817 |
| After: `--hidden`, excluding `.git/` | 4.843 s | 991,527 | 1,125,516 |

These are single wall-clock runs, not app latency. Both exited 2 with usable output, matching the
existing partial-read policy. The earlier roughly 233k baseline did not apply all production defaults.
A throwaway Swift script outside the repo fed each real NUL-delimited list through the shipped
index-exclusion/parent-derivation policy and `ForkRipgrepQuery.search`. For `config`, `~/.config` changed
from absent to rank 1; `.config` and `config` both score 159 after the fix (previously 152 and 159).
The script and its output lists were removed. No repo harnesses, build, lint, audit or app ran.

The path-ranking comparison used the exact `ForkRipgrepPolicy.arguments` with the Dev channel's
configured ignore patterns (none), the shipped exclusion policy and parent-directory derivation.
`rg` exited 2 with 991,578 usable files; the immutable index contained **1,125,568** file/folder rows.
The throwaway Swift driver compiled the shipped query/model/scorer sources with `swiftc -O
-whole-module-optimization` and fed the same home-relative, marker-free paths to Homebrew fzf 0.74.5
using `--filter QUERY --scheme=path --read0 --print0`, with default-options overrides cleared.

All eight queries shared at least four top-five paths. Seven matched all five; `config` shared four
because of the retained `.config` exception. All of fzf's top ten remained in Tinycast's returned rows.
A systematic, evenly spaced **300,000-row subset** of that real snapshot measured approximately
**41–64 ms** per query (median of three runs, including row metadata, excluding indexing and debounce).
The full snapshot measured **123–189 ms** in the same comparison. It is substantially larger than
the earlier 233k baseline; subset timings must not be presented as full-index latency. Unicode, cold metadata and type-filter retries can vary.

The full-snapshot oracle top fives (paths relative to home, in rank order):

| Query | Tinycast top five | fzf top five | Overlap | 300k median ms | Full index ms |
| --- | --- | --- | ---: | ---: | ---: |
| `strdbtntsx` | `work/stardust-design-system/packages/react/src/components/card/card-button.tsx`<br>`work/_patterns_census/stardust/packages/react/src/components/card/card-button.tsx`<br>`work/user_home/src/app/_components/RunSeedsButton.tsx`<br>`work/_patterns_census/src/user_home/src/app/_components/RunSeedsButton.tsx`<br>`work/account_hub/src/components/ResendInvitationButton.tsx` | Same paths and order | 5/5 | 43 | 142 |
| `strdst/btntsx` | `work/stardust-design-system/packages/phoenix/test/stardust_phoenix/buttons_test.exs`<br>`work/_patterns_census/stardust/packages/phoenix/test/stardust_phoenix/buttons_test.exs`<br>`work/_patterns_census/stardust/packages/react/src/components/button/button.tsx`<br>`work/_patterns_census/stardust/packages/nova/src/pages/design-system/ButtonsPage.tsx`<br>`work/_patterns_census/stardust/packages/react/src/components/button/button.test.tsx` | Same paths and order | 5/5 | 41 | 124 |
| `btntsx` | `work/ariel/js/pages/Participants/components/Header/InviteBtn.tsx`<br>`work/_patterns_census/src/ariel/js/pages/Participants/components/Header/InviteBtn.tsx`<br>`work/ariel/js/pages/Institution/InstitutionParticipants/components/invite/InstitutionParticipantsInviteBtn.tsx`<br>`work/_patterns_census/src/ariel/js/pages/Institution/InstitutionParticipants/components/invite/InstitutionParticipantsInviteBtn.tsx`<br>`work/ariel/js/components/Button/Button.tsx` | Same paths and order | 5/5 | 46 | 128 |
| `config` | `.config`<br>`.aws/config`<br>`.ssh/config`<br>`.kit/config`<br>`.gemini/config` | `.aws/config`<br>`.ssh/config`<br>`.kit/config`<br>`.gemini/config`<br>`.mc/config.json` | 4/5 | 44 | 153 |
| `agentkit` | `github/agentkit`<br>`.local/share/agentkit`<br>`github/agentkit/bin/agentkit-mcp`<br>`.cache/agentkit-cutover-20261011-132058`<br>`LangolfVault/1 - Projects/Agent Infrastructure/agentkit — Design.md` | Same paths and order | 5/5 | 44 | 123 |
| `readme` | `.kit/README.md`<br>`.kit-old/README.md`<br>`work/dns/README.md`<br>`github/fx/README.md`<br>`work/ariel/README.md` | Same paths and order | 5/5 | 52 | 153 |
| `fnav` | `.rustup/toolchains/stable-aarch64-apple-darwin/share/doc/rust/html/std/thread/fn.available_parallelism.html`<br>`.rustup/toolchains/1.94.0-aarch64-apple-darwin/share/doc/rust/html/std/thread/fn.available_parallelism.html`<br>`.rustup/toolchains/1.92.0-aarch64-apple-darwin/share/doc/rust/html/std/thread/fn.available_parallelism.html`<br>`.rustup/toolchains/stable-aarch64-apple-darwin/share/doc/rust/html/std/thread/functions/fn.available_parallelism.html`<br>`.rustup/toolchains/1.94.0-aarch64-apple-darwin/share/doc/rust/html/std/thread/functions/fn.available_parallelism.html` | Same paths and order | 5/5 | 58 | 189 |
| `tinycast palette` | `github/tinycast/Tinycast/Palette`<br>`github/tinycast/Tinycast/Fork/Palette`<br>`github/tinycast/docs/features/palette.md`<br>`github/tinycast/Tests/palette-tab-test.swift`<br>`github/tinycast/Tinycast/Windows/PaletteChips` | Same paths and order | 5/5 | 64 | 182 |

The requested `strdbtntsx` expectation conflicts with the oracle: fzf ranks Stardust's
`components/card/card-button.tsx` first (score 177), while `components/button/button.tsx` is 79th
(score 156).
Tinycast follows the measured fzf ordering rather than adding a repo- or filename-specific boost.
The screenshot's `.docx` row also appears in ripgrep's own candidate list; its presence does not prove
Spotlight supplementation. The ready-index service branch returns before either Spotlight pass.
The comparison scripts and candidate files are disposable and removed after verification.

## Verification handoff

The original implementation session used source parsing and XcodeGen generation; the dot-entry
correction used the throwaway Swift reproducer and source parsing only. Whole-app Swift 6
type checking, runtime cancellation/isolation, memory, TCC omissions and latency remain for Claude.
No repo harnesses, builds, lint, fork audit, app launch or commits were requested or performed.

Potentially affected harnesses: `file-search-test`, `file-search-session-test`, `fork-search-test`,
`file-navigator-test`, `settings-file-test`, `settings-backup-test` and `settings-history-test`.
Ripgrep-specific ranking assertions must use whole-path scores and `pathname,length,index` ties,
relative-path anchors/exclusions, the `.config` exception, and the 200-to-1,000 metadata retry.
Existing Spotlight filename/folder weighting assertions remain valid. No repository test was edited.

The session harness source list needs the index/query/policy/process/engine files and `ProcessExit`;
the index accepts configuration values without an AppSettings dependency. Any settings-schema stubs
may need the engine property and its mirror conformance. Harness sources and runner remain unchanged.

Harness handoff: add expectations for `.config/`, `.zshrc`, `.github/` and `.env.example` inclusion;
`.git/`, compiled/custom ignore and fixed-root exclusion; `.gitignore` retention; hidden subtree roots
and descendants with reveal off/on; and `.config` ranking above deeper `config` results. Any external
recursive-hidden-exclusion assertions must be reversed. The existing `file-search-test` assertions
that `FileSearchQuery.isExcludedPath` rejects hidden paths remain valid for Spotlight; the ripgrep
query now uses its fork-owned policy instead. No existing repo assertion was changed.

## Decisions (2026-10-11)

- Sasha's search rule supersedes the original hidden-path exclusion: include dot files and dot folders
  in the home index and ⌘F (including the Swift fallback), retaining ignore patterns, `.git/`, home
  `Library/` and `.Trash/`, `.gitignore` in ripgrep, and package boundaries. ⌘⇧. affects direct listings
  only. Spotlight candidate generation and blank-query recents retain their existing behavior.
- Ripgrep ranks whole home-relative paths with fzf's path scheme and `pathname,length,index` ties.
  One leading filename dot stays neutral for undotted, unanchored terms; prefix anchors and negation
  apply to the relative path. Spotlight fallback scoring keeps its existing field semantics.
