#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
from collections import Counter
from pathlib import Path
import re
import subprocess
import sys

problems = []
document = Path("docs/fork.md").read_text()
hooks = re.findall(r"\| `([^`]+)` \| `(// FORK: [^`]+)` \|", document)
if not hooks:
    problems.append("docs/fork.md has no hook table")
for filename, tag in hooks:
    path = Path(filename)
    if not path.is_file() or not re.search(re.escape(tag) + r"(?![\w-])", path.read_text()):
        problems.append(f"{filename}: missing {tag}")

upstream_files = subprocess.check_output(
    ["git", "ls-tree", "-r", "--name-only", "upstream/main"], text=True).splitlines()
documented = set(hooks)
for filename in upstream_files:
    path = Path(filename)
    if not path.is_file() or path.suffix not in {".swift", ".sh", ".yml", ".md"}:
        continue
    for tag in set(re.findall(r"// FORK: [a-z][a-z0-9-]*", path.read_text())):
        if (filename, tag) not in documented:
            problems.append(f"{filename}: undocumented {tag}")

search = Path("Tinycast/Fork/ForkSettingsSearch.swift").read_text()
row = Path("Tinycast/Fork/ForkFontRow.swift").read_text()
if not (re.search(r'\.generalAppearance,\s*"Interface font"', search)
        and 'title: "Interface font"' in row and 'anchor: .generalAppearance' in row):
    problems.append("Fork font search entry and settings row no longer share a target")

removed = re.compile(
    r"\binterfaceFontFamily\b|\bunscaledMetrics\b|"
    r"\b(?:AppSettings|settings)\.metrics\b|\bInterfaceMetrics\.face\b|"
    r"\bInterfaceMetrics\([^)]*\bfontFamily\s*:", re.S)
for root in ("Tinycast", "Tests"):
    for path in Path(root).rglob("*.swift"):
        for match in removed.finditer(path.read_text()):
            problems.append(f"{path}: removed fork API: {match.group(0)}")

def upstream(filename):
    return subprocess.check_output(["git", "show", f"upstream/main:{filename}"], text=True)

def typography_block(source):
    return source[source.index("    enum Typography {"):source.index("    enum Colors {")]

theme = "Tinycast/DesignSystem/Theme.swift"
if typography_block(Path(theme).read_text()) != typography_block(upstream(theme)):
    problems.append(f"{theme}: typography must match upstream exactly")
if "ForkTypography" in Path(theme).read_text() or "typography-tokens" in Path(theme).read_text():
    problems.append(f"{theme}: typography belongs in InterfaceMetrics")
expected_theme = upstream(theme).replace(
    "Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })",
    "ForkColors.adaptive(dark: dark, light: light)  // FORK: color-tokens")
if Path(theme).read_text() != expected_theme:
    problems.append(f"{theme}: only the adaptive resolver may differ from upstream")
for filename in (
    "Tinycast/DesignSystem/SettingsComponents.swift",
    "Tinycast/DesignSystem/SteadySegmentedPicker.swift",
    "Tinycast/Features/HotKeys/UI/ShortcutRecorder.swift",
    "Tinycast/Features/HotKeys/UI/ShortcutRecorderPopover.swift",
):
    if Path(filename).read_text() != upstream(filename):
        problems.append(f"{filename}: must stay upstream")

# Settings stays native; all other direct token readers need an explicit symbol-only budget.
direct_tokens = {
    "Tinycast/DesignSystem/BarButton.swift": ["menuSymbolSize", "menuSymbolSize"],
    "Tinycast/DesignSystem/PopoverMenu.swift": ["menuSymbolSize", "menuSymbolWeight"],
    "Tinycast/Features/Notes/UI/NoteFormattingBar.swift": ["disclosure"],
    "Tinycast/Features/AI/UI/AIChatDetailView.swift": [
        "composerStop", "composerSend", "disclosure", "composerSymbol", "composerSymbol"],
    "Tinycast/Features/HotKeys/UI/ShortcutRecorder.swift": ["keyCap", "keyCap"],
    "Tinycast/Features/HotKeys/UI/ShortcutRecorderPopover.swift": ["compactKeyCap"],
}
for path in sorted(Path("Tinycast").rglob("*.swift")):
    filename = path.as_posix()
    if ("Settings" in path.parts or filename.startswith("Tinycast/Fork/") or filename in {
        theme, "Tinycast/DesignSystem/InterfaceMetrics.swift", "Tinycast/DesignSystem/SettingsComponents.swift"
    }):
        continue
    budget = Counter(direct_tokens.get(filename, []))
    for match in re.finditer(r"Theme\.Typography\.(\w+)", path.read_text()):
        token = match.group(1)
        if budget[token]:
            budget[token] -= 1
        else:
            problems.append(f"{filename}: direct Theme typography bypasses metrics: {token}")

# Exact expressions and counts keep an allowed symbol file from admitting new prose fonts.
allowed = {
    "Tinycast/DesignSystem/InlineArgumentFields.swift": [".system(size: 8, weight: .semibold)"],
    "Tinycast/DesignSystem/SettingsComponents.swift": [
        ".system(size: 11)", ".systemFont(ofSize: NSFont.smallSystemFontSize)"],
    "Tinycast/DesignSystem/SteadySegmentedPicker.swift": [
        ".systemFont(ofSize: NSFont.systemFontSize)"],
    "Tinycast/DesignSystem/SymbolImage.swift": [".system(size: size, weight: .regular)"],
    "Tinycast/DesignSystem/PopoverMenu.swift": [
        ".system(size: metrics.scaled(Theme.Typography.menuSymbolSize), "
        "weight: Theme.Typography.menuSymbolWeight)"],
    "Tinycast/Windows/About/AboutView.swift": [
        ".system(size: 15, weight: .semibold)", ".system(size: 13, weight: .medium)"],
    "Tinycast/Features/AI/UI/ChatComposerChips.swift": [".system(size: 9, weight: .semibold)"],
    "Tinycast/Features/AI/UI/ChatMarkdownRenderer.swift": [
        ".systemFont(ofSize: 1)", ".systemFont(ofSize: 1)"],
    "Tinycast/Features/Emoji/Settings/EmojiSettingsView.swift": [
        ".system(size: Theme.Size.emojiSkinToneGlyph)"],
    "Tinycast/Features/Emoji/UI/EmojiGridView.swift": [
        ".system(size: glyphSize)", ".system(size: size)"],
    "Tinycast/Features/Extensions/Settings/ExtensionAppearancePicker.swift": [
        ".system(size: side * 0.46, weight: .medium)"],
    "Tinycast/Features/Extensions/Settings/ExtensionStorePanel.swift": [
        ".system(size: 28, weight: .light)"],
    "Tinycast/Features/Extensions/Settings/ExtensionsSettingsView.swift": [
        ".system(size: Theme.Size.settingsRowIcon - Theme.Spacing.xs)"],
    "Tinycast/Features/Extensions/UI/ExtensionFormView.swift": [
        ".system(size: 9, weight: .bold)"],
    "Tinycast/Features/Extensions/UI/ExtensionImage.swift": [
        ".system(size: side * 0.72)",
        ".system(size: usesMenuSymbolStyle ? metrics.scaled(MenuSymbolStyle.size) : side * 0.62, "
        "weight: usesMenuSymbolStyle ? .medium : .regular)"],
    "Tinycast/Features/Extensions/UI/ExtensionListView.swift": [
        ".system(size: min(size.width, size.height) * 0.72)"],
    "Tinycast/Features/Extensions/UI/ExtensionMenuBarImage.swift": [
        ".systemFont(ofSize: size - 2)"],
    "Tinycast/Features/HotKeys/UI/ShortcutRecorder.swift": [".system(size: 11)"],
    "Tinycast/Features/Launcher/Settings/AppPickerPopover.swift": [".system(size: 14)"],
    "Tinycast/Features/Launcher/UI/CompactFavoritesRow.swift": [".system(size: 10)"],
    "Tinycast/Features/Onboarding/OnboardingCard.swift": [".system(size: 13, weight: .medium)"],
    "Tinycast/Features/Onboarding/OnboardingView.swift": [".system(size: 30, weight: .semibold)"],
    "Tinycast/Features/Notes/UI/NoteBlockLayoutFragment.swift": [
        ".systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize)",
        ".preferredFont(forTextStyle: .caption1)",
        ".systemFont(ofSize: decoration.bodyPointSize)"],
    "Tinycast/Features/Notes/UI/NoteHeadingMenuView.swift": [
        ".system(size: metrics.typography.menuSymbolSize, weight: metrics.typography.menuSymbolWeight)"],
    "Tinycast/Features/Quicklinks/UI/QuicklinkListView.swift": [".system(size: 10)"],
    "Tinycast/Features/Settings/Panes/GeneralSettingsView.swift": [
        ".system(size: Self.glyph[size] ?? 13, weight: .medium)"],
    "Tinycast/Features/Settings/Panes/PermissionsSettingsView.swift": [
        ".system(size: SettingsListMetrics.iconSize - Theme.Spacing.xs)"],
    "Tinycast/Features/Snippets/Settings/SnippetsSettingsView.swift": [
        ".system(size: Theme.Size.settingsRowIcon - Theme.Spacing.xs)"],
}
typography = {
    "Tinycast/DesignSystem/Theme.swift",
    "Tinycast/DesignSystem/InterfaceMetrics.swift",
    "Tinycast/Features/Notes/UI/NoteMarkdownTypography.swift",
}
font_call = re.compile(
    r"\.(?:system\s*\(\s*size\s*:|systemFont\s*\(\s*ofSize\s*:|preferredFont\s*\()")

def normalise(expression):
    expression = re.sub(r"//[^\n]*", "", expression)
    return re.sub(r"\s+", "", expression)

def expressions(source):
    for match in font_call.finditer(source):
        opening = source.index("(", match.start())
        depth = 1
        end = opening + 1
        while end < len(source) and depth:
            depth += (source[end] == "(") - (source[end] == ")")
            end += 1
        yield source[match.start():end], match.start()

def resolves_through_fork(source, offset):
    calls = list(re.finditer(r"ForkTypography\.(?:resolve|prose)\s*\(", source[:offset]))
    if not calls:
        return False
    between = source[calls[-1].end():offset]
    depth = 1
    for character in between:
        depth += (character == "(") - (character == ")")
        if depth == 0:
            return False
    return True

for path in sorted(Path("Tinycast").rglob("*.swift")):
    filename = path.as_posix()
    if filename.startswith("Tinycast/Fork/") or filename in typography:
        continue
    budget = Counter(normalise(value) for value in allowed.get(filename, []))
    source = path.read_text()
    for expression, offset in expressions(source):
        if resolves_through_fork(source, offset):
            continue
        key = normalise(expression)
        if budget[key]:
            budget[key] -= 1
        else:
            line = source.count("\n", 0, offset) + 1
            problems.append(f"{filename}:{line}: font bypasses typography: {expression}")

if problems:
    print("Fork audit failed:", file=sys.stderr)
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    sys.exit(1)
print(f"Fork audit passed ({len(hooks)} documented hooks; font and removed-API guards).")
PY
