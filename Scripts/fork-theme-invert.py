#!/usr/bin/env python3
"""Regenerate Tinycast/Fork/Theme/ForkColorThemePreset+Kitty.swift from kitty-themes.

Usage: Scripts/fork-theme-invert.py <kitty-themes checkout>/themes

Each kitty theme is mapped onto the ten colour slots. Its inverted twin keeps the theme's own pair:
the foreground becomes the background and the background becomes the text. Every other colour keeps
its OKLCH hue and chroma and moves in lightness until it stands out from the new background about as
much as it did before:
- UI colours: 3–4.5:1 (accent 3–3.2:1, because it's a fill).
- Normal terminal colours: 3–6:1. Bright terminal colours: 3–4.5:1.
- Greys (0, 7, 8, 15): exactly the contrast they had.
"""
import math
import re
import sys
from pathlib import Path

REVISION = "c9be61857a09"  # kovidgoyal/kitty-themes commit the colours were read from
OUT = Path(__file__).resolve().parent.parent / "Tinycast/Fork/Theme/ForkColorThemePreset+Kitty.swift"

# id, name, file, which kitty keys fill which slots; None synthesises a missing status hue.
THEMES = [
    ("yorumi-kraken", "Yorumi Kraken", "yorumi-kraken.conf",
     dict(surface="active_tab_background", accent="active_tab_foreground", border="inactive_border_color",
          success="color10", warning="color11", error="color9")),
    ("yorumi-abyss", "Yorumi Abyss", "yorumi-abyss.conf",
     dict(surface="active_tab_background", accent="color12", border="active_border_color",
          success="color2", warning="color3", error="color9")),
    ("wild-cherry", "Wild Cherry", "WildCherry.conf",
     dict(accent="cursor", success="color2", warning="color3", error="color1")),
    ("vague", "Vague", "vague.conf",
     dict(surface="selection_background", accent="url_color", success="color2", warning="color3",
          error="color1")),
    ("terafox", "Terafox", "Terafox.conf",
     dict(surface="selection_background", accent="active_border_color", border="inactive_border_color",
          success="color2", warning="color3", error="color1")),
    ("tender", "Tender", "tender.conf",
     dict(surface="active_tab_background", accent="color6", border="color8",
          success="color2", warning="color3", error="color1")),
    ("shadotheme", "shadotheme", "shadotheme.conf",
     dict(surface="active_tab_background", accent="url_color", success=None, warning=None, error="color2")),
    ("serendipity-midnight", "Serendipity Midnight", "Serendipity_Midnight.conf",
     dict(surface="color0", accent="color4", success=None, warning=None, error="color1")),
    ("sea-shells", "Sea Shells", "SeaShells.conf",
     dict(accent="cursor", border="color0", success=None, warning="color3", error="color1")),
    ("rose-pine", "Rosé Pine", "rose-pine.conf",
     dict(surface="active_tab_background", accent="url_color", border="selection_background",
          success="color4", warning="color3", error="color1")),
    ("bluloco-light", "Bluloco Light", "BlulocoLight.conf",
     dict(surface="tab_bar_background", accent="url_color", border="color15",
          success="color2", warning="color3", error="color1")),
]
SLOTS = ["background", "surface", "text", "secondaryText", "accent", "border", "success", "warning",
         "error", "terminal"]
STATUS_HUE = dict(success=145, warning=75, error=25)
GREYS = {0, 7, 8, 15}


# OKLab / OKLCH and WCAG contrast
def hex2rgb(h): h = h.lstrip("#")[:6]; return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
def rgb2hex(c): return "%02X%02X%02X" % tuple(round(max(0, min(1, v)) * 255) for v in c)
def lin(v): return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
def delin(v): return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


def rgb2oklch(c):
    r, g, b = map(lin, c)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def _oklch2linear(L, C, H):
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def oklch2rgb(L, C, H):
    """Into sRGB, lowering chroma until it fits, so lightness and hue survive."""
    for _ in range(40):
        if all(-1e-4 <= v <= 1 + 1e-4 for v in _oklch2linear(L, C, H)):
            break
        C *= 0.95
    return tuple(delin(max(0, min(1, v))) for v in _oklch2linear(L, C, H))


def lum(c): r, g, b = map(lin, c); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def contrast(a, b): x, y = lum(a) + 0.05, lum(b) + 0.05; return max(x, y) / min(x, y)
def mix(a, b, t): return tuple(x + (y - x) * t for x, y in zip(a, b))
def shift_lightness(c, d): L, C, H = rgb2oklch(c); return oklch2rgb(max(0, min(1, L + d)), C, H)


def at_contrast(col, bg, ratio):
    """`col`'s hue and chroma at the lightness that gives `ratio` against `bg`, or the most it can."""
    _, C, H = rgb2oklch(col)
    darker = lum(bg) > 0.18
    ratio = min(ratio, contrast(oklch2rgb(0.0 if darker else 1.0, C, H), bg) * 0.98)
    lo, hi = (0.0, rgb2oklch(bg)[0]) if darker else (rgb2oklch(bg)[0], 1.0)
    for _ in range(50):
        mid = (lo + hi) / 2
        enough = contrast(oklch2rgb(mid, C, H), bg) >= ratio
        if darker:
            lo, hi = (mid, hi) if enough else (lo, mid)
        else:
            lo, hi = (lo, mid) if enough else (mid, hi)
    return oklch2rgb(lo if darker else hi, C, H)


def parse(path):
    keys = {}
    for line in path.read_text().splitlines():
        m = re.match(r"\s*(\w+)\s+(#[0-9a-fA-F]{6})", line)
        if m:
            keys[m.group(1)] = hex2rgb(m.group(2))
    return keys


def build(themes_dir, tid, name, file, picks):
    k = parse(themes_dir / file)
    bg, fg = k["background"], k["foreground"]
    ansi = [k[f"color{i}"] for i in range(16)]
    slots = dict(background=bg, text=fg, terminal=bg,
                 surface=k[picks["surface"]] if "surface" in picks else mix(bg, fg, 0.06),
                 secondaryText=mix(fg, bg, 0.40), accent=k[picks["accent"]],
                 border=k[picks["border"]] if "border" in picks else mix(bg, fg, 0.16))
    vivid = [c for c in ansi[9:15] if rgb2oklch(c)[1] > 0.05] or [slots["accent"]]
    synthesised = []
    for slot, hue in STATUS_HUE.items():
        if picks[slot] is None:
            # The theme's typical bright lightness and chroma, at the status hue.
            Ls, Cs = zip(*[rgb2oklch(c)[:2] for c in vivid])
            slots[slot] = oklch2rgb(sum(Ls) / len(Ls), sum(Cs) / len(Cs), hue)
            synthesised.append(slot)
        else:
            slots[slot] = k[picks[slot]]
    return dict(id=tid, name=name, file=file, slots=slots, ansi=ansi, synthesised=synthesised)


def invert(theme):
    o, bg0 = theme["slots"], theme["slots"]["background"]
    bg, fg = o["text"], bg0
    L, C, H = rgb2oklch(bg)
    if L > 0.965:
        bg = oklch2rgb(0.955, C, H)
    if C > 0.07:
        bg = oklch2rgb(L, 0.07, H)
    if contrast(bg, fg) < 7:
        fg = at_contrast(fg, bg, 7.0)
    band = lambda c, low, high: at_contrast(c, bg, min(high, max(low, contrast(c, bg0))))
    slots = dict(background=bg, text=fg, terminal=bg,
                 surface=shift_lightness(bg, -0.035 if lum(bg) > 0.18 else -0.025),
                 border=mix(bg, fg, 0.18),
                 secondaryText=at_contrast(o["secondaryText"], bg, max(4.5, contrast(o["secondaryText"], bg0))),
                 accent=band(o["accent"], 3.0, 3.2))
    for slot in ("success", "warning", "error"):
        slots[slot] = band(o[slot], 3.0, 4.5)
    ansi = [at_contrast(c, bg, contrast(c, bg0)) if i in GREYS else band(c, 3.0, 6.0 if i < 8 else 4.5)
            for i, c in enumerate(theme["ansi"])]
    return dict(id=theme["id"] + "-inverted", name=theme["name"] + " Inverted", slots=slots, ansi=ansi)


def swift_entry(theme, group, comment):
    def rows(colors, per):
        hexes = ["0x" + rgb2hex(c) for c in colors]
        return ",\n                ".join(", ".join(hexes[i:i + per]) for i in range(0, len(hexes), per))
    return "\n".join([
        *[f"        // {line}" for line in comment],
        "        .init(",
        f'            "{theme["id"]}", "{theme["name"]}", group: .{group},',
        "            slots: [",
        "                " + rows([theme["slots"][s] for s in SLOTS], 9),
        "            ],",
        "            ansi: [",
        "                " + rows(theme["ansi"], 8),
        "            ])",
    ])


def main():
    themes_dir = Path(sys.argv[1])
    originals = [build(themes_dir, *spec) for spec in THEMES]
    kitty = []
    for t in originals:
        comment = [f"kitty-themes {REVISION}, themes/{t['file']}"]
        if t["synthesised"]:
            comment.append(", ".join(t["synthesised"]) + " synthesised: the palette has no such hue")
        kitty.append(swift_entry(t, "kitty", comment))
    inverted = [swift_entry(invert(t), "inverted", [f"{t['name']} inverted by Scripts/fork-theme-invert.py"])
                for t in originals]
    OUT.write_text(f"""import Foundation

/// Themes from kitty-themes, mapped onto the ten slots, and each one's inverted twin.
///
/// An inverted twin keeps the theme's own pair: its foreground becomes the background and its
/// background the text. Every other colour keeps its hue and chroma and moves in lightness until it
/// stands out from the new background as much as it did before (UI colours 3–4.5:1, terminal
/// colours 3–6:1, greys exactly). `Scripts/fork-theme-invert.py` regenerates this file.
extension ForkColorThemePreset {{
    static let kitty: [ForkColorThemePreset] = [
{",\n".join(kitty)}
    ]

    static let kittyInverted: [ForkColorThemePreset] = [
{",\n".join(inverted)}
    ]
}}
""")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
