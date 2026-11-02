> Codex implements groups 1–2 without tests, builds, typechecking, lint, or app launch.
> Claude owns group 3.

## 1. Card presentation

- [x] 1.1 Restyle the Fix marker with sparkles, Fix, and a Tab keycap; preserve expiry and position calculations.
- [x] 1.2 Render the preview and rewrite cards with original text, a replacement arrow and a plain copy icon, following the system appearance.
- [x] 1.3 Keep mode switching on keys 1–3 and arrows, with no mode controls on the card.
- [x] 1.4 Fit the panel to content with bounded, scrollable replacement text and system material.
- [x] 1.5 Present loading, streaming, completed, and error states without issue metadata.

## 2. Coordinator wiring

- [x] 2.1 Pass the captured target text to the preview and rewrite cards.
- [x] 2.2 Keep apply and dismiss on the existing keys; the card has no Accept or Dismiss buttons.
- [x] 2.3 Copy the completed suggestion to the general pasteboard without activating Tinycast.
- [x] 2.4 Preserve keyboard registration, apply flow, cancellation checks, and text-free logs.
- [x] 2.5 Add the Lyra card regression harness and caret-known serialization assertions.

## 3. Verification (Claude)

- [x] 3.1 Build Debug with no new warnings in the touched files.
- [x] 3.2 Run `openspec validate fork-lyra-suggestion-card --strict`.
- [ ] 3.3 Run `Scripts/fork-audit.sh`.
- [ ] 3.4 Check the marker, preview, rewrite, and long-text scrolling in light and dark mode.
- [ ] 3.5 Check Tab, Return, keypad Enter, Escape, keys 1–3, and arrow keys in a host app.
- [ ] 3.6 Check Copy and mode clicks while the host app retains focus.
- [ ] 3.7 Check loading, streaming, errors, mode changes, and the eight-second marker expiry.
- [ ] 3.8 Confirm the change contains only the two scoped Swift files and this OpenSpec folder.
