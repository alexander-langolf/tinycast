## Why

Inline completion needs a contextual model that learns completed words and works across ordinary editing applications.
Tinycast owns the native surface and the bundled service that supplies predictions.

## What Changes

- A standard-library Python service ranks words with trigram counts and a decaying usage cache.
- The app bundles the service and loads its existing private SQLite learned-word store.
- Tinycast shows a single-word suffix at a reported caret and accepts the suffix with Tab.
- A field without caret geometry uses a passive full-word chip below the field, or inside the focused window when its field frame is unavailable.
- Settings control completion, confidence, and excluded bundle IDs.
- The default exclusions are VS Code, Xcode, Zed, and 1Password.
- Typing leaves Lyra hidden; an explicit Lyra card or workflow marker suppresses autocomplete.
- The kitty Word Panel surface is retired, and the research ladder imports the repository service.

## Capabilities

### New Capabilities

- `fork-inline-autocomplete`: contextual ranking, persistent learning, bundled model service, and native inline completion across eligible apps.

### Modified Capabilities

None.

## Impact

Native code lives in `Tinycast/Fork/Autocomplete/`.
Python modules live in its `AutocompleteService/` resource folder.
AppCore owns the coordinator and drains companion and insertion work at termination.
Tagged upstream hooks cover lifecycle, settings, settings search, localization, and resource packaging.
Terminal integration belongs to phase 2 and is outside this change.
