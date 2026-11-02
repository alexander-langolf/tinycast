> Codex implements groups 1–4. Claude builds, runs the harnesses and `bun test`, updates the
> BetterTouchTool trigger and relaunches Dev. Group 5 is Sasha's check.

## 1. Primitives

- [x] 1.1 Add target handles and extend `selection_read` (design §1).
- [x] 1.2 Add `model_complete` with the `model` scope, and `text_replace`.
- [x] 1.3 Add `ui_preview` on the Quick Action panel, `ui_marker` on Lyra's marker, and `ui_result`.

## 2. Server

- [x] 2.1 Add `server/` with routes, auth, action loading, hot reload and last-valid fallback
  (design §2).
- [x] 2.2 Move `policy/` into `server/policy/` and `server/prompts/`. Copy the Quick Action
  prompts verbatim.
- [x] 2.3 Add `rewrite.ts`, `fix-grammar.ts` and `lyra-fix-selection.ts` (design §6).

## 3. Tinycast wiring

- [x] 3.1 Add `ForkWorkflowServer` under the process supervisor, with the token file, the
  `workflows` client and health (design §3).
- [x] 3.2 Carry the correlation ID through the server and the router, and merge server events in
  `tinycast logs` (design §4).
- [x] 3.3 Forward link-safe `run/<name>` links. Route Rewrite and Fix Grammar to the server, with
  the native fallback (design §5).
- [x] 3.4 Remove `lyra_offer`. List every hook in `docs/fork.md`, and add `docs/features/workflows.md`
  and `server/README.md`.

## 4. Tests

- [x] 4.1 `bun test` for the actions with fake primitives and for reload behaviour.
- [x] 4.2 Swift harnesses for handles, `model_complete` arguments, link forwarding and the server
  environment.

## 5. Check (Sasha)

- [ ] 5.1 Run Rewrite from the hotkey and confirm the server handled it in `tinycast logs`.
- [ ] 5.2 Edit `server/prompts/rewrite.txt`, run Rewrite again, and confirm the change without a
  rebuild.
- [ ] 5.3 Select words in Slack and apply the BetterTouchTool-offered fix.
