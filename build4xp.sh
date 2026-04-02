#!/usr/bin/env bash
# build4xp.sh — build the Windows XP 32-bit target from project root
#
# Requires: i686-w64-mingw32-g++ (mingw-w64 package)
#   Ubuntu/Debian : sudo apt install mingw-w64
#
# Output: dist/packJPG_win_xp.exe

set -euo pipefail
cd "$(dirname "$0")"

DIST="dist"
mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

WIN32_XP="i686-w64-mingw32-g++"

if ! command -v "$WIN32_XP" &>/dev/null; then
    fail "$WIN32_XP not found. Install with: sudo apt install mingw-w64"
fi

if [[ ! -f source4xp/Makefile ]]; then
    fail "source4xp/Makefile not found"
fi

echo ""
echo "==> Building Windows XP 32-bit (source4xp/)"
(cd source4xp && make)

if [[ -f source4xp/bin/packJPG_win_xp.exe ]]; then
    cp source4xp/bin/packJPG_win_xp.exe "$DIST/"
    ok "dist/packJPG_win_xp.exe"
else
    fail "Build succeeded but output binary not found"
fi

echo ""
echo "Output: $DIST/packJPG_win_xp.exe ($(du -h "$DIST/packJPG_win_xp.exe" | cut -f1))"
echo ""
