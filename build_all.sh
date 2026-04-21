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
#
# Requirements: clang++ (or g++), mingw-w64
#   Ubuntu/Debian : sudo apt install mingw-w64
#   Arch          : sudo pacman -S mingw-w64-gcc
#   macOS         : brew install mingw-w64

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="source"
SRC="aricoder.cpp bitops.cpp packjpg.cpp"
CFLAGS="-I. -O3 -Wall -funroll-loops -ffast-math -fomit-frame-pointer -std=c++17"
CFLAGS_NATIVE="$CFLAGS -march=native"
# LTO gives ~8% encode speedup via cross-TU inlining (clang only; guard below)
CFLAGS_LTO="-flto=thin"
DIST="dist"

mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
skip() { echo "[--]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

# ─── Linux x64 ───────────────────────────────────────────────────────────────

echo ""
echo "==> Linux x64"
if command -v clang++ &>/dev/null; then
    CXX="clang++"
    # clang supports -flto=thin; apply to Linux builds for ~8% encode speedup
    LTO="$CFLAGS_LTO"
elif command -v g++ &>/dev/null; then
    CXX="g++"
    LTO=""  # skip LTO on g++ to avoid linker plugin complexity in CI
else
    fail "No C++ compiler found (clang++ or g++ required)"
fi

(cd "$SRC_DIR" && $CXX $CFLAGS $LTO -DUNIX \
    -o "../$DIST/packJPG_linux_x64" \
    $SRC \
    && strip --strip-unneeded "../$DIST/packJPG_linux_x64")
ok "dist/packJPG_linux_x64"

# native build (optimized for this machine only, not for distribution)
(cd "$SRC_DIR" && $CXX $CFLAGS_NATIVE $LTO -DUNIX \
    -o "../$DIST/packJPG_linux_x64_native" \
    $SRC)
ok "dist/packJPG_linux_x64_native (native, do not distribute)"

# ─── Windows x64 ─────────────────────────────────────────────────────────────

echo ""
echo "==> Windows x64"
WIN64="x86_64-w64-mingw32-g++"
WINDRES64="x86_64-w64-mingw32-windres"
if ! command -v "$WIN64" &>/dev/null; then
    skip "$WIN64 not found — skipping Windows x64"
    skip "Install with: sudo apt install mingw-w64"
else
    ICONS64=""
    if command -v "$WINDRES64" &>/dev/null; then
        (cd "$SRC_DIR" && $WINDRES64 -O coff icons.rc -o icons_x64.o \
            && echo "    [OK] icons compiled for x64" \
            || echo "    [!!] icon compilation failed — binary will have no icon")
        [ -f "$SRC_DIR/icons_x64.o" ] && ICONS64="icons_x64.o"
    else
        echo "    [!!] $WINDRES64 not found — binary will have no icon"
    fi

    (cd "$SRC_DIR" && $WIN64 $CFLAGS \
        -o "../$DIST/packJPG_win_x64.exe" \
        $SRC $ICONS64 \
        -static -static-libgcc -static-libstdc++ \
        && x86_64-w64-mingw32-strip --strip-unneeded "../$DIST/packJPG_win_x64.exe")
    [ -f "$SRC_DIR/icons_x64.o" ] && rm -f "$SRC_DIR/icons_x64.o"
    ok "dist/packJPG_win_x64.exe"
fi

# ─── Windows x86 (32-bit) ────────────────────────────────────────────────────

echo ""
echo "==> Windows x86 (32-bit)"
WIN32="i686-w64-mingw32-g++"
WINDRES32="i686-w64-mingw32-windres"
if ! command -v "$WIN32" &>/dev/null; then
    skip "$WIN32 not found — skipping Windows x86"
    skip "Install with: sudo apt install mingw-w64"
else
    ICONS32=""
    if command -v "$WINDRES32" &>/dev/null; then
        (cd "$SRC_DIR" && $WINDRES32 -O coff icons.rc -o icons_x86.o \
            && echo "    [OK] icons compiled for x86" \
            || echo "    [!!] icon compilation failed — binary will have no icon")
        [ -f "$SRC_DIR/icons_x86.o" ] && ICONS32="icons_x86.o"
    else
        echo "    [!!] $WINDRES32 not found — binary will have no icon"
    fi

    (cd "$SRC_DIR" && $WIN32 $CFLAGS \
        -o "../$DIST/packJPG_win_x86.exe" \
        $SRC $ICONS32 \
        -static -static-libgcc -static-libstdc++ \
        && i686-w64-mingw32-strip --strip-unneeded "../$DIST/packJPG_win_x86.exe")
    [ -f "$SRC_DIR/icons_x86.o" ] && rm -f "$SRC_DIR/icons_x86.o"
    ok "dist/packJPG_win_x86.exe"
fi

# ─── Windows XP 32-bit ───────────────────────────────────────────────────────

echo ""
echo "==> Windows XP 32-bit (source4xp/)"
if [[ ! -f source4xp/Makefile ]]; then
    skip "source4xp/Makefile not found — skipping XP build"
elif ! command -v "$WIN32" &>/dev/null; then
    skip "$WIN32 not found — skipping Windows XP build"
    skip "Install with: sudo apt install mingw-w64"
else
    (cd source4xp && make)
    if [[ -f source4xp/bin/packJPG_win_xp.exe ]]; then
        cp source4xp/bin/packJPG_win_xp.exe "$DIST/"
        ok "dist/packJPG_win_xp.exe"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Release binaries in $DIST/:"
ls -lh "$DIST"/ 2>/dev/null | grep -v '^total' || echo "  (none)"
echo ""
