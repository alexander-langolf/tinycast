## Context

`MonacoEditorCoordinator` supplies the document and Tinycast appearance defaults to `MonacoWebHost.Options`.
`ForkPolicyStore.current` exposes the active owner and its configurable server directory.
The page receives JavaScript arguments through `callAsyncJavaScript` and loads only bundled resources.

## Goals / Non-Goals

**Goals:**

- Keep personal editor settings and an unchanged theme JSON in the project folder.
- Apply file edits on the next editor open without rebuilding.
- Preserve Tinycast's existing editor appearance as the failure fallback.
- Cover parsing, option mapping, and page theme conversion without a web view.

**Non-Goals:**

- Reading VS Code preferences or loading extension code at runtime.
- Watching configuration files while an editor is open.
- Changing editor return, save, or keyboard behaviour.

## Decisions

### The web host loads each open's profile

`MonacoWebHost` snapshots the active policy directory for each open.
An owned task loads both files off the main actor and checks cancellation and opening identity before applying the result.
The host cancels the task when another open replaces the request or the host is destroyed.
The host waits for both settings and page readiness before opening the buffer.
The coordinator retains its existing contract and close-return harness.

### Models own decoding and option mapping

`MonacoSettings` validates the required configuration fields and resolves the relative theme path.
`MonacoTheme` decodes the theme's type, colours, scopes, foregrounds, and font styles.
`MonacoEditorOptions`, aliased as `MonacoWebHost.Options`, carries the parsed profile and maps the page arguments.
The loader accepts an injected reader for isolated harness coverage.
The mapper accepts an injected font-availability check.

### The page converts the theme

The page defines `tinycast-project` with `inherit: true` and a base selected from the theme's type.
Monaco receives VS Code colour identifiers with their original hexadecimal values.
Each token scope produces a rule; comma-separated scopes also produce individual rules.
Token foregrounds lose the leading hash and retain alpha; font styles retain explicit resets.
The page's appearance callback keeps the custom theme while the profile is active.
The host preserves the project font during Tinycast font-preference changes.

### A failed profile restores all defaults

Missing files, invalid JSON, invalid values, and unavailable fonts discard the project profile.
The editor uses the app's built-in theme, Tinycast's monospaced font at size 13, enabled minimap, and disabled wrapping.
The host records a typed `ForkEvent` with a policy-failure reason and no path or file contents.
The event uses the existing supervision health fallback shape.
The failure produces no dialog.

### A separate change owns the project-file scope

`monaco-project-settings` documents this implementation.
`monaco-vscode-settings-and-return` remains intact because its live VS Code import describes a different capability.

## Risks / Trade-offs

- VS Code token scopes map directly to Monaco rules; Monaco's bundled tokenizers determine the scopes available for highlighting.
- The host checks installed font families; the configuration does not install or distribute fonts.
- Page changes require one bundle rebuild into `Tinycast/Resources/MonacoEditor/` before native verification.
- XcodeGen registers the added Swift sources when the project is regenerated.

## Verification

Claude owns harness execution, bundle generation, project regeneration, Debug compilation, and native checks.
The JavaScriptCore harness evaluates the actual page glue with Monaco and WebKit message-handler stand-ins.
Native verification covers rendering, font resolution, app appearance changes, and settings edits applied after reopening.
