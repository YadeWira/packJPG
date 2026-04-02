#!/usr/bin/env bash
# build_all.sh — build all packJPG release targets from project root
#
# Targets:
#   Linux x64            (native, requires g++ or clang++)
#   Windows x64          (requires x86_64-w64-mingw32-g++)
#   Windows x86 / Win7   (requires i686-w64-mingw32-g++)
#   Windows XP 32-bit    (requires i686-w64-mingw32-g++, source4xp build)
#
# All binaries are collected into ./dist/

set -euo pipefail
cd "$(dirname "$0")"

DIST="dist"
mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
skip() { echo "[--]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

# ─── Main targets (Linux/Win7/Win64) via source/build_all.sh ─────────────────

echo ""
echo "==> Building Linux x64, Windows x64, Windows x86 (source/)"
if [[ ! -f source/build_all.sh ]]; then
    fail "source/build_all.sh not found"
fi

(cd source && bash build_all.sh)

# Copy outputs to dist/
for f in source/bin/packJPG_linux_x64 \
          source/bin/packJPG_linux_x64_native \
          source/bin/packJPG_win_x64.exe \
          source/bin/packJPG_win_x86.exe; do
    if [[ -f "$f" ]]; then
        cp "$f" "$DIST/"
        ok "dist/$(basename "$f")"
    fi
done

# ─── Windows XP 32-bit via source4xp/ ────────────────────────────────────────

echo ""
echo "==> Building Windows XP 32-bit (source4xp/)"
if [[ ! -f source4xp/Makefile ]]; then
    skip "source4xp/Makefile not found — skipping XP build"
else
    WIN32_XP="i686-w64-mingw32-g++"
    if ! command -v "$WIN32_XP" &>/dev/null; then
        skip "$WIN32_XP not found — skipping Windows XP build"
        skip "Install with: sudo apt install mingw-w64"
    else
        (cd source4xp && make)
        if [[ -f source4xp/bin/packJPG_win_xp.exe ]]; then
            cp source4xp/bin/packJPG_win_xp.exe "$DIST/"
            ok "dist/packJPG_win_xp.exe"
        fi
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Release binaries in $DIST/:"
ls -lh "$DIST"/ 2>/dev/null | grep -v '^total' || echo "  (none)"
echo ""
