## Why

Local Lyra (`~/github/local-lyra/app`) is a separate menu-bar writing assistant of 1,373 lines of
Swift. It offers Fix on pause, the Lyra rewrite command (default Hyper+R), and a local `llama-server` with Gemma 3n
E2B. It runs outside Tinycast, so its work has none of Tinycast's observability, supervision or
Automation access. Sasha decided to merge it into Tinycast and retire the standalone app.

## What Changes

- Local Lyra becomes a fork feature in `Tinycast/Fork/Lyra/`, with Fix, the rewrite panel and
  their hotkeys.
- `llama-server` becomes a supervised companion process with health reporting.
- Rewrites run through Tinycast's AI layer. The local model is an OpenAI-compatible connection
  to `llama-server`. The cloud option uses any Tinycast connection, such as the Claude account.
- Selection, focus and insertion go through the Core ports from `fork-core-capabilities`.
- The Automation API gains `lyra_rewrite`, so Script Kit can run a Lyra mode without the UI.
- Every Lyra step reports through `ForkTrace`. Lyra's own log file goes away.

## Capabilities

### New Capabilities

- `fork-local-lyra`: Fix, the rewrite panel, the local model server and the headless rewrite.

### Modified Capabilities

None.

## Impact

- New fork files under `Tinycast/Fork/Lyra/` and `Tinycast/Fork/Core/`.
- Lyra's prompts move into Tinycast's resources.
- Tagged hooks in `AppCore.swift`, the settings and the Automation catalog and runner, listed in
  `docs/fork.md`.
- The standalone app stops after Sasha's parity check. The `bench/` harness stays in the Local
  Lyra repository.
