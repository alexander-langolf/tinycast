## 1. Configuration and models

- [x] 1.1 Add the project configuration and copy the supplied theme JSON without extension code.
- [x] 1.2 Add Foundation-only decoding, validation, relative theme resolution, and option mapping.
- [x] 1.3 Add a settings loader with an injected reader for harness coverage.

## 2. Editor integration

- [x] 2.1 Read the active policy directory on every editor open and reject stale asynchronous results.
- [x] 2.2 Pass the parsed settings and theme through `MonacoWebHost.Options`.
- [x] 2.3 Convert theme colours and scopes in the page and preserve the custom theme during appearance changes.
- [x] 2.4 Restore defaults for invalid files or missing fonts and record typed diagnostics without file contents.

## 3. Harness and documentation

- [x] 3.1 Add and register a harness for the shipped file, relative paths, fallback, reloads, mapping, and page conversion.
- [x] 3.2 Document project settings and the `monaco-editor` fork integration.
- [x] 3.3 Keep the older VS Code import proposal intact.

## 4. Verification owned by Claude

- [ ] 4.1 Run `node build.mjs` in `Scripts/monaco-bundle` and regenerate the Xcode project.
- [ ] 4.2 Run `monaco-settings-test`, `monaco-editor-test`, and `monaco-close-returns-test`.
- [ ] 4.3 Build Debug and run the required repository checks.
- [ ] 4.4 Run `openspec validate monaco-project-settings --strict`.
- [ ] 4.5 Verify the Dev editor's theme, font, line height, minimap, wrapping, and settings reload on reopen.
