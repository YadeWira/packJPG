#!/usr/bin/env bash
# build_legacy.sh — build the Windows legacy (XP/Vista/7/8) targets from project root
#
# Requires: i686-w64-mingw32-g++ and x86_64-w64-mingw32-g++ (mingw-w64 package)
#   Ubuntu/Debian : sudo apt install mingw-w64
#
# Output: dist/packJPG_win_legacy_x86.exe
#         dist/packJPG_win_legacy_x64.exe

set -euo pipefail
cd "$(dirname "$0")"

DIST="dist"
mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

WIN32="i686-w64-mingw32-g++"
WIN64="x86_64-w64-mingw32-g++"

if ! command -v "$WIN32" &>/dev/null; then
    fail "$WIN32 not found. Install with: sudo apt install mingw-w64"
fi
if ! command -v "$WIN64" &>/dev/null; then
    fail "$WIN64 not found. Install with: sudo apt install mingw-w64"
fi

if [[ ! -f sourcelegacy/Makefile ]]; then
    fail "sourcelegacy/Makefile not found"
fi

echo ""
echo "==> Building Windows legacy x86 + x64 (sourcelegacy/)"
(cd sourcelegacy && make)

for arch in x86 x64; do
    bin="sourcelegacy/bin/packJPG_win_legacy_${arch}.exe"
    if [[ -f "$bin" ]]; then
        cp "$bin" "$DIST/"
        ok "dist/packJPG_win_legacy_${arch}.exe"
    else
        fail "Build succeeded but $bin not found"
    fi
done

echo ""
echo "Output:"
for arch in x86 x64; do
    f="$DIST/packJPG_win_legacy_${arch}.exe"
    [[ -f "$f" ]] && echo "  $f ($(du -h "$f" | cut -f1))"
done
echo ""
