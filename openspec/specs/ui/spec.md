# UI appearance and theming

## Purpose

Capture Tinycast's implemented appearance and theming at commit `9f065751`, inspected on
2026-10-12. This is a current-state baseline, not a redesign proposal or a rendered visual audit.

The area covers application appearance, interface size, typography, colour themes, component
overrides, persistence, palette chrome and motion. Feature interaction belongs to its own area:
for example [file-browser](../file-browser/spec.md) owns browser preview interaction. Extension
layouts and extension icon customization remain feature-owned rather than becoming shared UI policy.

## Requirements

### Requirement: Default appearance follows the operating system

With Tinycast default colours, the application SHALL offer System, Light and Dark, defaulting to
System. System SHALL assign `nil` to `NSApp.appearance`; Light and Dark SHALL assign Aqua and
Dark Aqua. `Theme` SHALL supply the base visual tokens and adaptive colour pairs, with the original
dark values retained as the baseline.

#### Scenario: Follow macOS appearance
- **WHEN** System is selected with no applied colour theme
- **THEN** AppKit controls the effective appearance without a separate forced appearance

#### Scenario: Apply a colour theme
- **WHEN** a non-default colour theme is applied
- **THEN** its resolved background determines the app's light or dark base appearance
- **AND** the System/Light/Dark picker is disabled with an explanation
- **AND** returning to Tinycast default colours restores the stored appearance choice

### Requirement: Appearance settings expose size and palette presentation

Settings → Appearance SHALL expose Theme, Interface Size, interface and monospaced fonts, Window
Mode, compact favourites, cursor-display following, drag-to-reposition, Colours and component-token
sections. Interface Size SHALL offer Default, Large and Larger with scales 1.0, 1.1 and 1.2.
`InterfaceMetrics` SHALL project shared dimensions and typography at the selected scale.

#### Scenario: Fresh settings
- **WHEN** no corresponding preferences exist
- **THEN** Interface Size is Default, compact mode and dragging are off, cursor-display following
  is on, and compact favourites are enabled but their control depends on compact mode

#### Scenario: Scale a component token
- **WHEN** an overridden length or font token is marked as scaling
- **THEN** its value is interpreted in points at Default size and multiplied through InterfaceMetrics
- **AND** non-scaling tokens, including terminal grid font size and output insets, retain their values

### Requirement: Interface and monospaced fonts are separate preferences

The appearance pane SHALL offer searchable installed font families for interface prose and a
monospaced-family picker for fixed-width text. Each SHALL support a system default. Font resolution
SHALL preserve point size and choose available family members by shape traits and weight, falling
back to the original font when the requested family cannot resolve.

#### Scenario: Change a font
- **WHEN** either family is selected
- **THEN** it is immediately published through ForkTypography and persisted
- **AND** appearance-scoped hosting content rebuilds for the changed family

#### Scenario: Transfer settings
- **WHEN** the opt-in settings file is used
- **THEN** `appearance.interfaceFont` and `appearance.monoFont` mirror these preferences
- **AND** settings backups exclude both machine-installed font family choices

### Requirement: Colour themes use a draft before application

The Colours section SHALL edit a draft independently of the applied theme. Preset selection, colour
slot edits, imports and Window gradient SHALL update the preview. Apply SHALL commit the draft;
Revert SHALL restore the applied value. An external applied-theme change SHALL update a clean draft
but SHALL NOT replace pending local draft edits.

#### Scenario: Preview a preset
- **WHEN** the user selects an editor, kitty or inverted kitty preset
- **THEN** palette, agent-card and terminal-card previews show its resolved colours
- **AND** the live application theme remains unchanged until Apply

#### Scenario: Return to default colours
- **WHEN** Tinycast (default) is chosen and applied
- **THEN** the stored colour theme becomes nil and adaptive base colours resume

### Requirement: Theme slots resolve into existing surfaces

A colour theme SHALL define ten slots: window background, surface, text, secondary text, accent,
border, success, warning, error and terminal background. The resolver SHALL classify a background
as dark below luminance 0.179. Text and secondary text below 4.5:1 contrast against the background
SHALL be mixed toward white for dark bases or black for light bases in 5-percent steps.

#### Scenario: Contrast correction
- **WHEN** either text slot requires adjustment
- **THEN** the resolved palette uses the corrected ink
- **AND** the preview names the adjusted slot and its original ratio

#### Scenario: Resolve shared and fork colours
- **WHEN** an applied colour theme is active
- **THEN** the shared adaptive resolver maps recognized text, selection, hover, border and scrim
  pairs to theme slots, and the hosting scope applies the theme accent as tint
- **AND** unmatched adaptive pairs and fixed upstream status colours keep their existing behavior
- **AND** fork card surfaces can use the theme's success, warning and error slots

#### Scenario: Render a themed scrim
- **WHEN** a themed palette or terminal surface renders
- **THEN** its default themed opacity is 85 percent unless the relevant palette scrim token overrides it
- **AND** Window gradient blends its background toward the surface slot when enabled

### Requirement: Imports produce editable themes

The Colours section SHALL accept a comma-separated hex theme string or a VS Code theme file.
String import SHALL populate ordered slots and derive missing values. VS Code import SHALL map
supported `colors` keys, including editor background, and accept JSON comments. Copy Theme String
SHALL copy the draft's ten-slot colour string and SHALL be disabled for the nil default theme.

#### Scenario: Import succeeds
- **WHEN** theme input can be parsed
- **THEN** the imported theme becomes the preview draft and still requires Apply

#### Scenario: Import fails
- **WHEN** the selected file or text cannot produce a theme
- **THEN** the import UI displays a failure message without applying a theme

### Requirement: Component tokens apply live and preserve inherited defaults

The Agent Card, Terminal Instance and Palette sections SHALL expose the tokens declared in
`ForkThemeToken`, with their declared type and range. Edits SHALL publish immediately. Reset SHALL
remove an individual override or all overrides for the selected component. Setting a token through
the store to its current default SHALL remove its override.

#### Scenario: Inherit geometry
- **WHEN** card corner-radius tokens are unset
- **THEN** Agent Card and Terminal Instance radii follow the Palette radius
- **AND** an unset terminal bar height follows the compact header geometry

#### Scenario: Preserve adaptive ink
- **WHEN** a colour token is unset
- **THEN** the surface retains its adaptive or theme-resolved fallback
- **WHEN** that colour token is set
- **THEN** the single sRGB override applies in both appearances

The token groups currently cover agent-card padding, gaps, margin, radius, scrim, border, text
sizes, dot geometry and model ink; terminal bar height, gutter, radius, divider, grid font size and
output insets; and palette radius, row padding/radius, search-field font size, header padding,
light/dark scrim opacities and border. The source enum is the authoritative key/range inventory.

### Requirement: One owned store publishes the live theme

AppCore SHALL own ForkAppearance and ForkThemeStore and start them in that order. ForkThemeStore
SHALL publish a value through the observable, lock-protected ForkThemeState, consumed through
ForkTheme.current. Applied colour-theme or font-family changes SHALL change the identity of content
wrapped in ForkAppearanceScope so previously resolved colours and fonts can redraw.

#### Scenario: Persist and restore tokens
- **WHEN** token or applied colour-theme state changes
- **THEN** the store writes its `forkTheme` UserDefaults dictionary, removing the key when empty
- **AND** settings backups carry the appearance-token map and colour theme
- **AND** backup restoration replaces the token set and theme while ignoring unusable entries

#### Scenario: Edit the settings mirror
- **WHEN** `appearance.tokens` is updated
- **THEN** omitted token entries retain their values, null resets named tokens, unknown or unusable
  entries report issues, and numeric values are clamped to their declared ranges
- **AND** `colorTheme: null` restores default colours
- **AND** `appearance.theme` remains the separate System/Light/Dark preference

### Requirement: Terminal theming has an explicit renderer boundary

The Ghostty grid SHALL consume theme text, terminal background and accent as foreground,
background and cursor defaults, and use supplied preset/imported ANSI colours when present.
The ANSI palette SHALL remain data rather than ten-slot UI controls. Program-supplied OSC colours
can override defaults. The fallback TerminalLogView SHALL retain its own rendering rules.

#### Scenario: Customize terminal geometry
- **WHEN** grid font size or output insets change
- **THEN** the Ghostty grid uses those token values
- **AND** the fallback log does not gain those same font/inset overrides

### Requirement: Palette motion honors Reduce Motion

Palette presentation SHALL use centralized motion values for window resizing and staggered block
reveals. Window-frame transitions SHALL settle immediately under Reduce Motion; reveal modifiers
SHALL remove offsets and stagger while retaining a short fade.

#### Scenario: Normal presentation transition
- **WHEN** a visible palette changes frame with Reduce Motion off
- **THEN** its frame uses the 0.34-second non-bouncing spring and a shrink delay when applicable
- **AND** block reveals use their configured ordering and offsets

#### Scenario: Reduced presentation motion
- **WHEN** Reduce Motion is enabled
- **THEN** frame changes jump to their target and reveal modifiers use a 0.15-second fade with no slide

### Requirement: Palette chrome combines native glass and theme-owned decoration

The palette SHALL render its current ForkTheme scrim over GlassEffectView, which creates an
NSGlassEffectView. Its continuous rounded clip SHALL follow the frame animator's radius while
animating and the supplied resting radius otherwise. The optional palette border SHALL use its
configured colour or adaptive fallback and SHALL NOT intercept input.

#### Scenario: Enable the palette border
- **WHEN** the palette border token is enabled
- **THEN** the border follows the same shape as the palette clip
- **AND** border width remains a non-scaling token

## Implementation map

Paths are relative to the repository root; grouped filenames share their directory.

| Responsibility | Source |
| --- | --- |
| Base tokens and scaled projections | `Tinycast/DesignSystem/Theme.swift`, `InterfaceMetrics.swift` |
| Appearance and size choices | `Tinycast/Features/Settings/AppAppearance.swift`, `InterfaceSize.swift`, `AppSettings.swift` |
| Ownership and AppKit appearance | `Tinycast/App/AppCore.swift` |
| Appearance pane and draft controls | `Tinycast/Fork/Appearance/AppearanceSettingsView.swift`, `ForkColorThemeSection.swift`, `ForkThemeTokenRow.swift` |
| Font selection and resolution | `Tinycast/Fork/ForkFontRow.swift`, `FontCatalog.swift`, `ForkTypography.swift` |
| Live redraw scope | `Tinycast/Fork/ForkAppearance.swift`, `ForkAppearanceScope.swift` |
| Theme data and persistence | `Tinycast/Fork/Theme/ForkTheme.swift`, `ForkThemeToken.swift`, `ForkThemeStore.swift`, `ForkThemeState.swift`, `ForkThemeSettingsFile.swift`, `ForkThemeBackup.swift` |
| Colour resolution and import | `Tinycast/Fork/Theme/ForkColorTheme.swift`, `ForkColorPalette.swift`, `ForkVSCodeTheme.swift`, `ForkInk.swift` |
| Palette motion and clipping | `Tinycast/Fork/Motion/PaletteMotion.swift`, `PaletteReveal.swift`, `PaletteFrameAnimator.swift`, `PaletteFrameClip.swift` |

## Evidence and limits

This baseline is source-inspected. Existing harnesses include `Tests/appearance-test.swift`,
`interface-size-test.swift` and `fork-layer-test.swift`. They do not establish that every theme,
font, display size, renderer or contrast combination works visually. No builds, tests or browser/app
inspection were run to create this artifact.

- `docs/ui.md` describes the adaptive upstream look. Its behind-window blur description does not
  identify the current NSGlassEffectView implementation. `docs/features/appearance-theme.md`
  documents the fork customization layer; a fixed dark scrim is not the full themed behavior.
- InterfaceMetrics scales consumers that use it; it is not a promise that every native settings
  control, feature-owned layout or fixed terminal measurement scales uniformly.
- Nonstandard metric dimensions round to whole points. Standard metrics equal the base Theme
  only while the corresponding fork overrides are unset.
- Font replacement reaches wired typography consumers, not every system control or symbol.
- Contrast adjustment covers two resolved inks against the theme background, not all semantic
  colours, translucent combinations, wallpapers, selection states or arbitrary token overrides.
- Component colour overrides have no separate light/dark values. The row token controls padding,
  not a universal row height. Palette radius does not redefine dialog radius.
- Applied theme/font changes rebuild scoped hosting trees; this baseline makes no claim that every
  local view state survives that rebuild. Numeric token updates use live observation instead.
- Theme-string export represents slots, not a full export of ANSI data, gradient, fonts or tokens.
- Theme-string import skips invalid fragments, accepts comma/semicolon/whitespace separators,
  and uses only the first ten valid colours. The documentation's "up to ten" is not a rejection limit.
- Default-valued overrides are cleared by the UI store setter, but settings-file import stores
  accepted values explicitly. Such an override can stop following an inherited default.
- Upstream dialogs and HUDs keep fixed status hues; terminal fallback output keeps its own styling.
- Motion values are source constants, not Appearance settings. Reveal triggers may replay when
  content is inserted or a supplied mode key changes, not only when the palette first opens.
- Palette Reduce Motion handling is not an app-wide guarantee: dialog entrance has its own
  movement and fade. No explicit Reduce Transparency or Increase Contrast handling was found;
  native glass behavior remains delegated to AppKit.

Related documentation: `docs/ui.md`, `docs/features/appearance-theme.md`,
`docs/features/palette-motion.md`.

### Requirement: Inactive launcher remains visible at half scale

While Tinycast is running in ordinary unlocked desktop use, the inactive launcher SHALL present one
main-launcher field at uniform visual scale 0.5. The field SHALL contain the launcher search glyph
and neutral placeholder, centred horizontally 4 points below the selected display's menu/notch-safe
top boundary. It SHALL scale resolved normal header geometry, typography and decoration together,
and SHALL NOT display results, favourites, auxiliary chips, footer or a retained query.

#### Scenario: Start without invoking the launcher
- **WHEN** Tinycast finishes starting with no active palette session
- **THEN** the half-scale field appears without changing the frontmost app or keyboard focus
- **AND** no interactive palette session is started merely to display it

#### Scenario: Appearance or interface size changes
- **WHEN** the current theme, font, size or applicable header token changes while resting
- **THEN** the resting field updates and remains half the resolved normal header size

### Requirement: Invocation moves and scales the resting field into the active palette

The existing summon hotkey and clicking or accessibility-activating the resting field SHALL invoke
the palette. Normal-motion invocation SHALL animate uniform scale from 0.5 to 1.0 and translation
to the existing active placement using a non-bouncing 0.34-second transition. Only one perceived
launcher field SHALL be visible, and results/body SHALL reveal at the destination.

#### Scenario: Invoke with hotkey
- **WHEN** the user invokes the resting launcher with its hotkey
- **THEN** it transitions to normal scale at the existing resolved palette position
- **AND** active compact/full presentation and existing mode-restoration rules are preserved

#### Scenario: Click the resting field
- **WHEN** the user clicks or accessibility-activates the resting field
- **THEN** the main launcher opens on the field's display using the same transition

#### Scenario: Type during opening
- **WHEN** the user types immediately after invocation while the transition is running
- **THEN** the real palette accepts each keystroke once
- **AND** the travelling launcher header reflects that input without dropping or resetting it at handoff

#### Scenario: Open a feature directly
- **WHEN** an existing feature command or shortcut opens a non-launcher mode from rest
- **THEN** its mode, seed input and destination are preserved
- **AND** the resting representation yields to that active palette without a second visible field

### Requirement: Dismissal returns to the resting field without extending the session

An actual palette dismissal SHALL end the active session and return its header presentation to the
half-scale top position. Existing Escape navigation, pop-to-root policy, action completion and
focus-restoration semantics SHALL remain authoritative. The resting surface SHALL NOT count as an
active palette, accept text input or retain active-only search, input-source or feature work.

#### Scenario: Dismiss the active palette
- **WHEN** the palette is dismissed by its existing toggle, outside-click, Escape or completed action
- **THEN** active content is removed and the neutral header returns to the resting position
- **AND** teardown and requested focus restoration each occur once independently of animation completion

#### Scenario: Escape only navigates back
- **WHEN** existing Escape behavior closes a menu or navigates within the active palette
- **THEN** the palette stays active and does not return to rest until that behavior actually dismisses it

#### Scenario: Quit
- **WHEN** Tinycast terminates
- **THEN** resting, active and transitional surfaces and their owned observers are removed

### Requirement: Resting placement respects screens and Spaces

The feature SHALL maintain one resting field across available displays, initially using the existing
cursor-display/primary-display preference. It SHALL keep its display while idle, resolve hotkey
activation on the normal target display, and rest on the active display after dismissal. Cross-display
activation SHALL relocate the resting endpoint before animating locally rather than travel through
the space between displays. Idle geometry SHALL NOT overwrite saved active palette placement.

#### Scenario: Invoke on another display
- **WHEN** the normal hotkey target display differs from the resting field's display
- **THEN** one field transitions on the target display and none remains on the previous display

#### Scenario: Notch, display geometry or availability changes
- **WHEN** a display has a notch, changes usable geometry or is disconnected
- **THEN** resting placement is recomputed inside an available safe screen area
- **AND** the field does not occupy the reserved menu/notch region

#### Scenario: Change desktop Space or enter fullscreen
- **WHEN** the user changes Space, including an ordinary fullscreen Space
- **THEN** the resting field remains available on the active Space without switching focus or Spaces
- **AND** system-modal, lock and other OS-protected surfaces retain precedence

### Requirement: Transitions are interruptible and respect reduced motion

New summon/dismiss requests SHALL retarget from the current presentation without queuing duplicate
transitions. Stale completion callbacks SHALL NOT change the latest intended state or focus.
Reduce Motion SHALL replace geometric travel with an immediate position/scale update and at most
a 0.15-second fade. The resting field SHALL expose an Open Tinycast accessibility action and SHALL
have no hit-test area outside its visible bounds.

#### Scenario: Rapidly reverse direction
- **WHEN** summon or dismissal reverses an in-flight transition
- **THEN** the presentation proceeds from its current geometry toward the latest requested endpoint
- **AND** only one active session and one perceived field remain

#### Scenario: Reduce Motion enabled
- **WHEN** invocation or dismissal occurs with Reduce Motion enabled
- **THEN** no scale/translation animation or stagger runs
- **AND** focus, session lifecycle and final geometry match normal-motion behavior

#### Scenario: Resting resource use
- **WHEN** the field is resting without relevant input or configuration changes
- **THEN** it runs no animation display link, repeated search refresh or active feature session
