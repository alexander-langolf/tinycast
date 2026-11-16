# Local Lyra

Local Lyra is a fork-owned writing assistant in `Tinycast/Fork/Lyra/`.
`AppCore` owns the coordinator and wires the AI provider factory and clipboard manager.

## Invariants

- Policy files own limits, modes, prompts, and connection routing.
- Typing initiates no Lyra request, marker, or temporary key registration.
- BetterTouchTool owns app and selection triggers through the `lyra-fix-selection` server action.
- Selection offers replace only the captured selection.
- Each request retains one policy snapshot and records the snapshot version.
- Secure fields and Tinycast's own windows produce no rewrite request.
- Kitty selections use remote control and produce Copy-only rewrite cards.
- Lyra never reads kitty's Accessibility value or writes into kitty.
- Every write validates the original field value, selection, element, and running application identified by the system-wide focused element.
- A newer edit or focus change invalidates an older suggestion.
- Empty and incomplete responses cannot be applied.
- Trace and audit records contain no user text, prompt, output, or token content.
- Shutdown stops only an owned model server and drains clipboard restoration.

## Settings

The Local Lyra connection appears in Settings under AI Providers.
The connection's Overview contains enable and model path controls.
Lyra defaults to enabled only when the configured model file exists.
The default model path is `~/github/local-lyra/bench/models/gemma-3n-E2B-it-Q4_K_M.gguf`.
An explicit enable preference persists across launches.
Disabled Lyra stops its focus observer and temporary card hotkeys.
The rewrite command's binding persists while Lyra is disabled, and invoking the command records `notEnabled` without presenting a card.

The opt-in settings file exposes `ai.lyraEnabled`, `ai.lyraModelPath`, and `ai.lyraPolicyDirectory`.
The retired `ai.lyraFixEnabled` key has no schema binding.
The stored typed-Fix preference is ignored.
`ai.lyraPolicyDirectory` mirrors the `fork.policy.directory` preference.
Policy routing accepts a connection UUID or `local` for each mode.
Each route uses the first model in the connection's model catalog.
`local` selects the fork-owned `Local Lyra` connection at `http://127.0.0.1:8765/v1`.
The bundled policy routes every mode to `local`.
`swift Scripts/fork-configure-vercel.swift` configures Vercel Haiku for the Dev channel while Tinycast is closed.
The setup copies the gateway credential between Keychain entries and retains the source entry.
The `Vercel Haiku` connection uses `anthropic/claude-haiku-5.5` with reasoning disabled.
Every Lyra mode and the Rewrite quick action use that connection in the configured channel.
The policy and prompts live in ignored `.local/vercel-lyra/`, selected through `fork.policy.directory`.
The setup preserves unrelated API connections and quick-action overrides.
Lyra starts the local model server only for a local request.
The obsolete `ai.lyraPanelConnection` key is unsupported.
An existing settings file must omit that key.
The local model identifier is `gemma-3n-e2b`.

## Runtime policy

The default policy directory is `~/github/tinycast/server`.
`server/policy/lyra.json` declares schema version 1, Fix limits and timing, selection limits, modes, and routing.
Each mode names a prompt file under `server/prompts/`.
Mode names contain lowercase ASCII letters, digits, underscores, or hyphens, with a maximum of 32 characters.
The mode list accepts 1–16 unique names.
The rewrite panel places `fix` first and follows policy order for the remaining modes.
The hotkey requires a policy containing `fix`.
Additional modes appear with their policy names.
The default order is Fix, Refine, Professional, and Friendly.
The card displays the selected mode and previous-mode and next-mode buttons.

Word limits range from 1 to 10,000.
Character limits range from 1 to 100,000.
The minimum word count cannot exceed the character limit.
The policy schema accepts Fix pause values from 0 to 60,000 milliseconds.
These timing fields preserve existing policy-file decoding and harness contracts; typing does not use them.
Prompt files contain nonempty UTF-8 text and have a 256 KiB size limit.
Prompt filenames contain ASCII letters, digits, underscores, or hyphens and end in `.txt`.
Prompt paths cannot leave the server configuration root through traversal or symlinks.

`ForkPolicyStore` reads policy files off the main actor.
DispatchSource monitors the policy files, prompt directory, policy directory, and existing parent directories.
A 150-millisecond settling period groups filesystem events.
The monitor reopens descriptors after atomic saves and directory replacement.
A valid edit publishes an immutable snapshot without a restart.
The snapshot version is a 12-character hexadecimal SHA-256 prefix over filenames and file bytes.
A policy change invalidates pending requests and suggestions.
A rejected edit records the filename and a fixed failure category and preserves the last valid snapshot.
A missing directory uses the bundled policy and prompt folders.
An invalid initial policy also uses the bundled folder when no valid snapshot exists.
`project.fork.yml` bundles `server/policy/` and `server/prompts/` as folder resources.
The bundle contains the same source files as the runtime directory.

## Controls

Typing and selection changes only invalidate stale Lyra state.
They initiate no Fix request and show no Lyra marker.
The workflow server retains its explicit selection-marker path and two-Tab preview and apply controls.

“Rewrite with Lyra” opens the rewrite panel from the palette or its configurable hotkey.
The command uses the `sparkles` symbol and appears in Settings under Commands.
The opt-in settings file exposes the shortcut through `commands.builtIn` under `lyra-rewrite`.
The command retains Lyra's enable setting and runtime policy gates.
The card starts Fix on the selection or on the entire field when the selection is empty.
The hotkey uses the panel rewrite path without the automatic Fix word-count and character-count gate.
The headless Fix and workflow selection limits retain their existing policies.
An empty field or whitespace-only target shows the existing message HUD with “Nothing to check”.
Input events timestamped before a card opens cannot dismiss that card through a delayed monitor callback.
Observer callbacks preserve a card when its captured field, value, and selection remain current.

`ForkLyraHotKey` seeds Hyper+R before the hotkey manager loads stored bindings.
The seed uses `KeyShortcut.hyperChord(includesShift:)` with the user's Include Shift setting.
The binding lives at `hotkey.command:lyra-rewrite` in the app channel's UserDefaults.
The one-time flag is `fork.lyra.panelHotKeySeeded`.
The first attempt records the flag, including attempts skipped for an existing binding or an occupied chord.
The seed preserves any stored Lyra binding and refuses Hyper+R when another stored action holds the chord.
Later launches preserve unbinding and rebinding choices without another seed attempt.

Keys 1–4 select the first four panel modes, and the arrow keys cycle through all panel modes.
The card's previous-mode and next-mode buttons also cycle through the modes.
Tab, Return, and keypad Enter accept a completed response.
Acceptance applies the response in editable fields and copies it for kitty before dismissing the card.
Escape closes the panel.
For Accessibility targets, the panel rewrites the selection when a selection exists and the whole field otherwise.

## Kitty selections

“Rewrite with Lyra” reads kitty through `ForkKittySelectionSource`, an adapter for the `ForkSelectionSource` port.
The adapter recognises bundle ID `net.kovidgoyal.kitty`.
The adapter resolves `Contents/MacOS/kitten` from the running application's bundle URL.
The command targets `unix:/tmp/kitty.sock-<pid>` using the kitty process identifier reported by the system-wide focused element.
This address follows the configured `listen_on unix:/tmp/kitty.sock` base and kitty's process suffix.
The adapter does not discover other socket configurations.

The adapter launches kitten directly with `@ --to unix:<socket> get-text --match state:focused --extent selection`.
The read has a one-second deadline.
Cancellation and timeout terminate and reap the owned kitten process.
The adapter bounds output at 4 MiB and discards standard error.
A selection span records text length, bundle ID, and numeric error code without text or socket contents.

The card shows the captured selection as the original and streams the selected policy mode's rewrite.
The card appears near the captured mouse position and stays within that display's visible frame as the card grows.
The service validates cancellation, request identity, and the focused element's running application during streaming.
Kitty requests require no Accessibility text value, selection range, or caret bounds.
Tab, Return, and keypad Enter copy a completed rewrite to the general pasteboard and dismiss the card.
The copy icon copies the completed rewrite and keeps the card visible.
Loading, partial responses, and errors disable copying.
The kitty path has no insertion callback, and the service rejects writes to kitty.

An empty selection shows “Select text in kitty first”.
A failed read shows “Lyra can't read kitty's selection”.
Neither case opens a card.
The kitty card starts in Fix and retains Refine, Professional, and Friendly.
The focus observer excludes kitty before reading Accessibility text.
The headless `lyra_rewrite` tool rejects kitty targets.

`ForkSelectionAdapters` excludes the kitty adapter.
Rewrite and Fix Grammar quick actions retain their shared selection and paste delivery path.
Terminal-safe delivery for those quick actions requires a separate change.

## Accessibility and delivery

The system-wide focused element supplies the target process identifier.
`NSRunningApplication` resolves that identifier and rejects terminated applications.
Snapshot checks and insertion use the same focused-element and running-process identity.
The focus observer attaches to that process and replaces an observer attached to a different process.
The observer replaces value and selection subscriptions when the focused field changes.
The caret lookup tries an empty range, the next UTF-16 character, and the previous UTF-16 character.
A previous-character result anchors the marker at the trailing edge.
Missing caret bounds use the field's bottom-right corner.
The panel converts Accessibility coordinates into AppKit coordinates and stays within the visible display frame.

The Lyra sink tries an Accessibility selected-text replacement and verifies the field value.
A stable failed write falls back to System Events paste.
The sink preserves surrounding text when a control transforms a partial Accessibility replacement.
The clipboard lease preserves every available clipboard representation.
The sink restores the clipboard after 500 milliseconds only while the lease retains ownership.
Tinycast's clipboard capture bookkeeping excludes the temporary rewrite.
Accessibility permission enables observation, and Automation permission allows System Events paste.

## Model server

`ForkProcessSupervisor` owns the lifecycle through the injectable `ForkProcessControl` boundary.
`ForkLlamaServer` probes `/health` on port 8765 and reuses a healthy server.
An unhealthy occupied port produces a failed state without terminating the listener.
The adapter starts `/opt/homebrew/bin/llama-server` with the configured model on a free port.
Server output goes to the null device.
The feature creates no separate log file.

The channel-specific `Lyra/server.pid` record includes PID, executable path, and process birth time.
Adoption verifies the recorded identity and the process's port-8765 listener.
Shutdown rechecks process identity before signalling an owned process.
Shutdown leaves reused servers running.
Health responses expose state, ownership, and the owned PID in `processes`.

## Automation and diagnostics

`lyra_rewrite` requires the `selection` client scope.
The tool accepts `mode`, optional `target`, and optional `apply`.
Modes come from the active policy.
The default modes are `fix`, `refine`, `professional`, and `friendly`.
Targets are `automatic`, `selection`, and `field`.
`automatic` uses the selection for panel modes and the whole field for Fix.
`apply` defaults to false.
The response contains `text` and `applied`.
The service uses the focused external field without opening the palette or panel.

The `lyra-fix-selection` server action checks selection limits and generates the Fix response.
The action uses `ui_marker` and polls `ui_result` for completion.
The marker applies only to a valid captured selection handle.
The [workflow guide](workflows.md) describes run links and primitive scopes.
Selection actions use the feature enable setting and retain the workflow marker.
Tinycast selection notifications dismiss stale suggestions and never initiate a selection offer.

`tinycast logs --op lyra` filters correlated Lyra events.
Events report trigger, offer, request, first-token timing, marker, insertion path, dismissal, and policy reload.
Each `openPanel()` invocation records `trigger` before checking enablement, policy, or focus.
Every rejected invocation records a `decision` event with a fixed `reason` code.
Reasons include `notEnabled`, `busy`, `noPolicy`, `noFix`, `noFocusedElement`, `protected`, `noSelection`, and `emptyField`.
These hotkey decisions have no rate limit.
The fields contain lengths, known roles, bundle identifiers, process identifiers, and fixed codes without user text.
Lyra request events carry the captured `policyVersion`, including automation start and end events.
`tinycast health` lists the model server alongside companion app health.
The policy harness covers strict decoding, runtime modes, UUID routing, version changes, last-valid fallback, atomic saves, and prompt watching.
The model harness covers policy limits, cleaning, prompt contents, and tool arguments.
The supervision and stream harnesses cover fake process control and complete responses.
Runtime policy and selection checks belong to `fork-policy-split` group 4.
Hotkey-card and typing checks belong to `fork-lyra-hotkey-only`.
The typing-trigger portions of `fork-local-lyra` are superseded by that change.
