#!/bin/bash
# FORK: prototype. Builds libghostty-vt as an XCFramework into .tools/libghostty/.
# Needs Zig 0.16.0 at .tools/zig-0.16.0 (official tarball, see docs/features/libghostty-prototype.md).
set -euo pipefail

GHOSTTY_COMMIT=246f702876b924a1cb7cade1e99274d1470302fc
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
ZIG="${ZIG:-$TOOLS/zig-0.16.0/zig}"
SRC="$TOOLS/ghostty"
OUT="$TOOLS/libghostty"

[ -x "$ZIG" ] || { echo "Zig not found at $ZIG" >&2; exit 1; }
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/ghostty-org/ghostty.git
fi
git -C "$SRC" fetch -q --depth 1 origin "$GHOSTTY_COMMIT"
git -C "$SRC" checkout -q --force "$GHOSTTY_COMMIT"

(cd "$SRC" && "$ZIG" build -Demit-lib-vt -Doptimize=ReleaseFast)

rm -rf "$OUT"
mkdir -p "$OUT"
XC="$(find "$SRC/zig-out" -name '*.xcframework' -maxdepth 3 | head -1)"
[ -n "$XC" ] || { echo "no xcframework in $SRC/zig-out" >&2; exit 1; }
cp -R "$XC" "$OUT/"
echo "libghostty-vt @ $GHOSTTY_COMMIT -> $OUT/$(basename "$XC")"
