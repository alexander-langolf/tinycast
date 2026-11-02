## Context

`fork-local-lyra` ported Local Lyra into `Tinycast/Fork/Lyra/`. Its rules are Swift constants:

- `ForkLyraText.delay(for:)`: at least 3 words, at most 1,000 characters, 500 ms, or zero after
  ending punctuation.
- `selectionTriggerApps` and `selectionDelay`, added after the merge.
- The prompt files in `Tinycast/Resources/LyraPrompts`.
- The panel connection setting.

`fork-core-capabilities` added the `selection` scope, `tinycast call` and router tracing.

## Goals / Non-Goals

**Goals:**

- A trigger rule changes without a Tinycast build.
- A limit, prompt or routing change takes effect on the next call without a restart.
- A broken policy file never breaks Lyra.

**Non-Goals:**

- A policy server process. It stays optional until a flow needs logic that is neither a
  BetterTouchTool condition nor data.
- Moving Fix-on-pause triggering to BetterTouchTool. BetterTouchTool has no "typing paused" event.
- Policy for subsystems other than Lyra. Later slices follow the same pattern.

## Decisions

### 1. Three homes for rules

| Rule | Home |
| --- | --- |
| Which app, which gesture, selection or hotkey | BetterTouchTool trigger and condition group |
| Word and length limits, delays, mode list, prompts, model routing | `policy/` files |
| Reading, model calls, insertion, UI, logging | Tinycast |

### 2. Policy files are data with a schema

`policy/lyra.json` holds `schemaVersion`, `fix` (`minWords`, `maxCharacters`, `pauseMs`,
`punctuationEndsPause`), `selection` (`minWords`, `maxCharacters`), `modes` (name and prompt file)
and `routing` (a connection name per mode, or `"local"`). `policy/prompts/` holds one text file per
prompt.

`ForkPolicyStore` loads the folder and decodes it strictly. Unknown keys and out-of-range values
are rejected. The store computes a short hash of the files as the policy version. A file watcher
reloads the folder on change. A failed reload logs the rejection with the file name and the
failure, and the last valid version stays active.

### 3. The folder location is a setting

The default location is the repository's `policy/` folder: `~/github/tinycast/policy`, stored as
`fork.policy.directory`. When the folder is missing, Tinycast uses the copy bundled in the app,
built from the same files.

### 4. `lyra_offer` reuses the Fix marker

`lyra_offer` takes `mode` (default `fix`) and `target` (default `selection`). Tinycast reads the
focused field and checks the `selection` limits from policy. It runs the mode, then shows the
marker at the selection. Tab and Return behave as in typed Fix. The tool returns `{offered,
reason}` without text. It needs the `selection` scope.

### 5. The BetterTouchTool preset lives in the repository

A preset named `Tinycast` holds the following:

- a Conditional Activation Group with the condition `bundleIdentifier is com.tinyspeck.slackmacgap`;
- inside it, a "Text Selection Did Change" trigger;
- an action that runs the Dev CLI: `tinycast call lyra_offer --args '{"mode":"fix"}' --channel dev
  --client <btt client id>`.

`btt/tinycast.bttpreset` is the exported preset. `btt/README.md` describes how to import it, how
to export it, and the BetterTouchTool client that needs the `selection` scope.

### 6. Decisions record the policy version

Each Lyra trigger and offer event carries the policy version as a field.

## Risks / Trade-offs

- **BetterTouchTool detects only mouse selections.** A keyboard selection needs BetterTouchTool's
  manual detection shortcut.
- **Slack selection reading through BetterTouchTool is unproven.** Tinycast reads the selection
  through its own Accessibility observer, so the BetterTouchTool trigger only signals the event.
- **The preset is not plain text.** The repository copy is exported and imported; reviews diff
  the trigger JSON that `get_triggers` returns.
