# Fork search: Spotlight subsequence-glob spike

**Question:** can Spotlight return fuzzy file candidates fast enough with a subsequence glob
(`kMDItemFSName == "*f*o*r*k*"cd`), or does fuzzy file search need a path index of its own?

**Verdict (2026-10-08): the glob loses. Task 10 of `docs/superpowers/plans/2026-10-08-fzf-search.md` is not done.**
File search keeps upstream Spotlight retrieval with the fzf rerank it already has; true fuzzy file search
needs its own path index, planned separately.

Pass bar: median glob latency ≤ 150 ms for 3–8 letter terms, and under 1,000 results for terms of 4+ letters.
Both fail: the glob is 2–3× slower than the substring query and every 4+ letter term except long rare ones
hits the 1,000-result cap, so the rerank would see an arbitrary slice.

`mdfind -onlyin $HOME`, `head -1000`, three runs, median ms. The CLI adds ~350 ms of process overhead
(zero-result queries take ~355 ms), so absolute numbers overstate in-app latency; the comparison and the
result counts do not depend on it.

| Term | Substring results | Substring ms | Glob results | Glob ms |
| --- | ---: | ---: | ---: | ---: |
| fork | 374 | 513 | 1000 | 1392 |
| forktypo | 1 | 359 | 3 | 423 |
| invmarch | 0 | 357 | 0 | 373 |
| ariel | 233 | 451 | 1000 | 1221 |
| pkg | 357 | 455 | 1000 | 1216 |
| agenda | 26 | 371 | 1000 | 1029 |
| sigils | 37 | 372 | 1000 | 814 |
| stardust | 975 | 494 | 1000 | 450 |
| tc | 1000 | 1268 | 1000 | 1637 |

Script: `prototypes/spotlight-glob-spike.sh` on branch `prototype/fuzzy-search`.
