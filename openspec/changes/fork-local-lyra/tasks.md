> Codex implements groups 1–4. Claude builds, runs the harnesses and relaunches Dev. Group 5 is
> Sasha's parity check.

## 1. Model and server

- [x] 1.1 Add the Lyra model: trigger rule, output cleaning, modes and prompts in Tinycast
  resources (design §1).
- [x] 1.2 Add `ForkLlamaServer` as a supervised process companion (design §3).
- [x] 1.3 Register the "Local Lyra" connection (design §2).

## 2. Engine and UI

- [x] 2.1 Port the focus observer and engine onto the ports (design §1, §4).
- [x] 2.2 Port the marker, the panel and the hotkeys (design §5).
- [x] 2.3 Add settings: enable, Fix, model path and panel connection.

## 3. Headless and observability

- [x] 3.1 Add `ForkLyraService` and the `lyra_rewrite` tool (design §6).
- [x] 3.2 Trace every Lyra step (design §7).
- [x] 3.3 List every hook in `docs/fork.md`, and add `docs/features/lyra.md`.

## 4. Harnesses

- [x] 4.1 Cover the trigger rule, output cleaning, prompt loading, server reuse and adoption with a
  fake process control, and `lyra_rewrite` argument validation.

## 5. Parity check (Sasha)

- [ ] 5.1 Run Local Lyra's README manual checks 2–8 against Tinycast Dev.
- [ ] 5.2 Quit the standalone Local Lyra app and remove it from login items.
