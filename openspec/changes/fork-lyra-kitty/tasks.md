> The worker implements groups 1–2 without tests, builds, typechecking, lint, or app launch.
> Claude owns group 3.

## 1. Selection and rewrite

- [x] 1.1 Add the kitty selection adapter with bundle-relative kitten resolution and process-specific arguments.
- [x] 1.2 Bound the child process read, propagate cancellation, and record text-free trace metadata.
- [x] 1.3 Route the rewrite command before Accessibility reads and map empty or failed reads to a HUD.
- [x] 1.4 Share streaming between snapshot targets and plain text with no apply parameter for plain text.
- [x] 1.5 Exclude kitty from Fix on pause and reject Lyra writes into kitty.
- [ ] 1.6 Resolve the selection-source kind within the authorised port scope.

## 2. Card, harness, and documentation

- [x] 2.1 Present a Copy-only card near the captured pointer and retain visible-frame placement during streaming.
- [x] 2.2 Copy completed responses on Return and keypad Enter before dismissal, without calling apply.
- [x] 2.3 Keep the copy icon available only for completed responses and preserve the card after a copy click.
- [x] 2.4 Author the kitty harness and register the harness without changing existing tests.
- [x] 2.5 Document socket selection, Fix exclusion, and the shared quick-action delivery follow-up.
- [x] 2.6 Regenerate the Xcode project for added Swift sources.

## 3. Verification (Claude)

- [ ] 3.1 Run every `fork-lyra-*` harness and `fork-observability-test`.
- [ ] 3.2 Build Debug without new warnings.
- [ ] 3.3 Run `openspec validate fork-lyra-kitty --strict`.
- [ ] 3.4 Synchronise localized strings and translate the new HUD messages into all supported languages.
- [ ] 3.5 Select text in kitty, invoke Hyper+R, and check the captured original and pointer placement.
- [ ] 3.6 Check Return, keypad Enter, and the copy icon without terminal insertion.
- [ ] 3.7 Check empty selection, unavailable socket, timeout, cancellation, and application switches.
- [ ] 3.8 Check mode switching, partial responses, errors, and Fix exclusion in kitty.
