> Codex implements groups 1–2. Claude builds BetterTouchTool group 3 through BTT MCP, then builds,
> runs the harnesses and relaunches Dev. Group 4 is Sasha's check.

## 1. Policy store

- [x] 1.1 Create `policy/lyra.json` and `policy/prompts/` from today's values (design §2).
- [x] 1.2 Add `ForkPolicyStore` with strict decoding, version hash, file watching and last-valid
  fallback in `Tinycast/Fork/Core/Policy/` (design §2, §3).
- [x] 1.3 Make Lyra read limits, delays, modes, prompts and routing from the store. Remove
  `selectionTriggerApps` and `selectionDelay` and the selection trigger in `ForkLyraCoordinator`.
  Record the policy version on Lyra events (design §6).

## 2. Tool

- [x] 2.1 Add `lyra_offer` (design §4).
- [x] 2.2 Harnesses: policy decoding and rejection, version change, fallback to the last valid
  policy, `lyra_offer` argument validation and selection limits.
- [x] 2.3 Update `docs/features/lyra.md` and `docs/fork.md`.

## 3. BetterTouchTool

- [ ] 3.1 Build the `Tinycast` preset with the Slack condition group and the selection trigger
  (design §5).
- [ ] 3.2 Export it to `btt/tinycast.bttpreset` and write `btt/README.md`.

## 4. Check (Sasha)

- [ ] 4.1 Create the BetterTouchTool automation client with the `selection` scope.
- [ ] 4.2 Select words in Slack and apply the offered fix with two Tab presses.
- [ ] 4.3 Change `fix.minWords` while Dev runs and confirm the change takes effect without a
  rebuild.
