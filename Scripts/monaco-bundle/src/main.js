import * as monaco from "../node_modules/monaco-editor/esm/vs/editor/editor.api.js";
import { createTokenizationSupport } from "../node_modules/monaco-editor/esm/vs/languages/features/json/tokenization.js";

// The json language service needs a worker, so only its tokenizer is registered.
monaco.languages.register({ id: "json", extensions: [".json", ".jsonc", ".webmanifest"], aliases: ["JSON"] });
monaco.languages.setTokensProvider("json", createTokenizationSupport(true));

const post = (message) => window.webkit.messageHandlers.tinycast.postMessage(message);
let editor;
let savedVersion = 0;
let reportedDirty = false;
let projectTheme;

function reportDirty() {
  const dirty = editor.getModel().getAlternativeVersionId() !== savedVersion;
  if (dirty === reportedDirty) return;
  reportedDirty = dirty;
  post({ type: "dirty", dirty });
}

function convertTheme(theme) {
  const rules = [];
  for (const entry of theme.tokenColors) {
    const scopes = Array.isArray(entry.scope) ? entry.scope : [entry.scope ?? ""];
    for (const group of scopes) {
      for (const scope of group.split(",")) {
        const rule = { token: scope.trim() };
        if (entry.settings.foreground !== undefined) {
          rule.foreground = entry.settings.foreground.replace(/^#/, "");
        }
        if (entry.settings.fontStyle !== undefined) rule.fontStyle = entry.settings.fontStyle;
        rules.push(rule);
      }
    }
  }
  return {
    base: theme.type === "light" ? "vs" : "vs-dark",
    inherit: true,
    colors: { ...theme.colors },
    rules,
  };
}

function create(options) {
  projectTheme = undefined;
  if (options.projectTheme) {
    monaco.editor.defineTheme("tinycast-project", convertTheme(options.projectTheme));
    projectTheme = "tinycast-project";
  }
  editor = monaco.editor.create(document.getElementById("root"), {
    value: options.text,
    language: options.language,
    theme: projectTheme ?? options.theme,
    fontFamily: options.fontFamily,
    fontSize: options.fontSize,
    lineHeight: options.lineHeight,
    wordWrap: options.wordWrap,
    automaticLayout: true,
    minimap: { enabled: options.minimap },
    scrollBeyondLastLine: false,
    renderWhitespace: "selection",
    smoothScrolling: true,
    contextmenu: false,
  });
  savedVersion = editor.getModel().getAlternativeVersionId();
  reportedDirty = false;
  editor.onDidChangeModelContent(reportDirty);
  editor.addCommand(
    monaco.KeyCode.Escape,
    () => post({ type: "close" }),
    "!suggestWidgetVisible && !findWidgetVisible && !parameterHintsVisible && !inSnippetMode",
  );
  editor.focus();
  post({ type: "ready" });
}

window.tinycastEditor = {
  open(options) {
    if (editor) editor.dispose();
    create(options);
  },
  snapshot: () => ({ text: editor.getValue(), version: editor.getModel().getAlternativeVersionId() }),
  markSaved(version) {
    savedVersion = version;
    reportDirty();
  },
  setTheme: (theme) => monaco.editor.setTheme(projectTheme ?? theme),
  setFont: (family, size) => editor.updateOptions({ fontFamily: family, fontSize: size }),
  focus: () => editor.focus(),
};
