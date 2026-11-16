## ADDED Requirements

### Requirement: Typing does not present Lyra

Typing, pauses, punctuation, and selection changes SHALL initiate no Lyra Fix request, marker, or suggestion.
Hidden Lyra SHALL register no temporary Tab or Escape key.
The UI and settings-file schema SHALL contain no typed-Fix setting.

#### Scenario: Ordinary typing
- **WHEN** the user types or pauses in an editable field
- **THEN** Lyra remains hidden and makes no automatic rewrite request

### Requirement: The hotkey fixes the captured target

The Lyra command, default Hyper+R, SHALL start Fix on the selection when one exists and the whole focused field otherwise.
The existing suggestion card SHALL show the result.
The hotkey SHALL use the panel rewrite path without the automatic Fix size gate.

#### Scenario: Whole field
- **WHEN** the user invokes Lyra with an empty selection in a focused field
- **THEN** Fix receives the entire field and a completed acceptance replaces that field

#### Scenario: Selection
- **WHEN** the user invokes Lyra with a nonempty selection
- **THEN** Fix receives only that selection and acceptance preserves surrounding text

### Requirement: The card retains tone controls and acceptance keys

Fix SHALL be the first card mode, followed by the configured tone modes.
The default card SHALL retain Refine, Professional, and Friendly.
Mode buttons, arrow keys, and keys 1–4 SHALL select the default four modes.
Tab, Return, and keypad Enter SHALL accept only a completed successful response.
Escape SHALL dismiss the card.

#### Scenario: Tone change
- **WHEN** the user selects Professional inside a Fix card
- **THEN** Lyra rewrites the same captured target in Professional mode

#### Scenario: Partial response
- **WHEN** the user presses Tab or Enter before a response completes
- **THEN** Lyra applies or copies no partial response

### Requirement: Kitty retains Copy-only rewriting

The existing kitty selection path SHALL start in Fix and retain its remote-control selection reader.
Acceptance SHALL copy the completed result and dismiss the card without writing into kitty.

#### Scenario: Kitty selection
- **WHEN** the user invokes Lyra on a kitty selection and accepts a completed Fix
- **THEN** Tinycast copies the result and performs no terminal insertion

### Requirement: Workflow markers retain their lifecycle

The workflow server SHALL retain explicit marker presentation, preview, application, dismissal, and completion callbacks.
Typing-only removal SHALL preserve workflow selection replacement and writing ownership.

#### Scenario: Workflow marker
- **WHEN** a workflow presents a valid captured selection marker
- **THEN** the first Tab previews its result and the second Tab applies through the workflow callback

### Requirement: Explicit Lyra suppresses autocomplete

A Lyra card or workflow marker SHALL dismiss ghost text and release autocomplete keys before Lyra registers its keys.
Secure fields and Tinycast windows SHALL produce no hotkey rewrite.
Stale field, selection, application, and policy identities SHALL invalidate the result.

#### Scenario: Card ownership
- **WHEN** Hyper+R opens a card while a ghost is visible
- **THEN** the ghost disappears and autocomplete registers no Tab while the card is open

#### Scenario: Secure field
- **WHEN** the hotkey is invoked in a secure field or protected ancestor
- **THEN** Tinycast reads no field value and sends no rewrite request
