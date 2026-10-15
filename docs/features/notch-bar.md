# Notch bar

Fork-owned in `Tinycast/Fork/Notch/`, owned by `AppCore.notchBar`. The OpenSpec change is
`notch-slide-status-bar`; it replaces `persistent-launcher-field` and `notch-status-bar`.

## Invariants

- **Off by default.** `notchBarEnabled` (Settings → General → Show notch bar, `general.showNotchBar`)
  decides whether the bar exists. `NotchBarCoordinator.applyEnabled()` shows or hides it live; hidden
  means no panel, no probe, no observers and no Ghostty polling, because the bar starts and stops
  `ghosttyStatus`. `hide()` resets the policy so a later show works; only `stop()` is terminal.
  Turning it on while the palette is open starts the bar retracted.

- One passive panel sits at the top of the primary display (`NSScreen.primary`, never `.main`),
  one window level above the menu bar. It ignores the mouse, never becomes key or main, and never
  activates Tinycast. The bar is not clickable and exposes no actions.
- The bar is a path-masked fill. Its colour is the wallpaper's average over the menu bar band behind
  the bar (`NotchBackdropReader`, from `desktopImageURL`, so no permission), because a transparent
  menu bar is the wallpaper. With Reduce Transparency or no readable wallpaper it falls back to a
  `.menu` material blur, which samples whatever window lies behind and can look grey. Resampled on
  start, screen changes, Space changes and each time the bar expands. The panel's appearance comes
  from a zero-width `NSStatusItem` button so text matches the menu bar's own light or dark.
- `NotchGeometry` is pure. A real notch comes from `safeAreaInsets.top` and the auxiliary top areas;
  otherwise a 200-point virtual notch is centred and its collapsed height is 0. Collapsed and
  expanded paths have the same element sequence so Core Animation can interpolate them. Content sits
  below `contentTop` so it never falls inside the notch cut-out.
- `NotchPolicy` holds a target (expanded or retracted) and a transition identity. A superseded
  completion is dropped through `accepts(_:)`. Expanding slides the path then fades content in;
  retracting fades content out then slides. Reversal retargets from the presentation layer's path.
  Reduce Motion skips the slide and fades for 0.15 seconds.
- The palette shows and hides directly. `PaletteWindowController` calls `sessionDidStart` and
  `sessionDidEnd` (both idempotent); the bar never takes part in focus. Ghostty polling runs only
  while the bar is expanded.
- The entry is one icon, title and subtitle from `NotchEntry`: the selected tab of the first Ghostty
  window, with a Codex or Claude icon only for a verified association. Unavailable states show a
  neutral line. See [ghostty-tab-status.md](ghostty-tab-status.md).
- Sleep, screen lock and screen-parameter changes order the panel out or recompute its frame.

## Evidence boundary

`notch-test` covers geometry, path interpolation, policy and the entry. A Debug build checks
integration. The native check so far confirmed the bar renders centred on the primary display over
the menu bar with the menu bar's dark appearance. Not yet checked: slide timing, reversal on
invoke, the physical notch seam, light appearance, Spaces and fullscreen, Reduce Motion, and
external or notchless displays.
