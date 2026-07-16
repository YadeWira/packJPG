#!/usr/bin/env bash
# build_all.sh — build all packJPG release targets from project root
#
# Targets:
#   Linux x64                          (native, requires g++ or clang++)
#   Windows x64                        (requires x86_64-w64-mingw32-g++)
#   Windows legacy x86 (XP/Vista/7/8)  (requires i686-w64-mingw32-g++,    sourcelegacy build)
#   Windows legacy x64 (XP/Vista/7/8)  (requires x86_64-w64-mingw32-g++,  sourcelegacy build)
#
# Note: modern Windows x86 (32-bit Win10) was dropped — that audience is
# vanishingly small, and Win7/8 x86 users are better served by the legacy
# x86 build (which also runs on XP).
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

# JPEG-LS support (requires libcharls-dev + libjxl-dev): auto-detect via a
# throwaway link probe, same pattern as source/Makefile's JLS auto-detect.
# Windows/legacy targets below never get it — no mingw builds of those libs.
# JLS_LIBS must stay after $SRC/$JLS_SRC on the command line (linker order).
JLS_SRC=""
JLS_DEFINE=""
JLS_LIBS=""
if echo 'int main(){}' | $CXX $CFLAGS -x c++ -lcharls -ljxl -ljxl_threads -o /dev/null - 2>/dev/null; then
    JLS_SRC="jpegls.cpp"
    JLS_DEFINE="-DHAVE_JPEGLS"
    JLS_LIBS="-lcharls -ljxl -ljxl_threads"
    ok "JPEG-LS support detected (libcharls-dev + libjxl-dev found)"
else
    skip "JPEG-LS support disabled (libcharls-dev/libjxl-dev not found)"
fi

(cd "$SRC_DIR" && $CXX $CFLAGS $LTO -DUNIX $JLS_DEFINE \
    -o "../$DIST/packJPG_linux_x64" \
    $SRC $JLS_SRC $JLS_LIBS \
    && strip --strip-unneeded "../$DIST/packJPG_linux_x64")
ok "dist/packJPG_linux_x64"

# native build (optimized for this machine only, not for distribution)
(cd "$SRC_DIR" && $CXX $CFLAGS_NATIVE $LTO -DUNIX $JLS_DEFINE \
    -o "../$DIST/packJPG_linux_x64_native" \
    $SRC $JLS_SRC $JLS_LIBS)
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

# ─── Windows legacy x86 + x64 (XP/Vista/7/8) ─────────────────────────────────

echo ""
echo "==> Windows legacy x86 + x64 (sourcelegacy/)"
WIN32="i686-w64-mingw32-g++"
if [[ ! -f sourcelegacy/Makefile ]]; then
    skip "sourcelegacy/Makefile not found — skipping legacy build"
elif ! command -v "$WIN32" &>/dev/null; then
    skip "$WIN32 not found — skipping legacy build"
    skip "Install with: sudo apt install mingw-w64"
elif ! command -v "$WIN64" &>/dev/null; then
    skip "$WIN64 not found — skipping legacy x64 (legacy x86 alone built)"
    (cd sourcelegacy && make x86)
    [ -f sourcelegacy/bin/packJPG_win_legacy_x86.exe ] && \
        cp sourcelegacy/bin/packJPG_win_legacy_x86.exe "$DIST/" && \
        ok "dist/packJPG_win_legacy_x86.exe"
else
    (cd sourcelegacy && make)
    [ -f sourcelegacy/bin/packJPG_win_legacy_x86.exe ] && \
        cp sourcelegacy/bin/packJPG_win_legacy_x86.exe "$DIST/" && \
        ok "dist/packJPG_win_legacy_x86.exe"
    [ -f sourcelegacy/bin/packJPG_win_legacy_x64.exe ] && \
        cp sourcelegacy/bin/packJPG_win_legacy_x64.exe "$DIST/" && \
        ok "dist/packJPG_win_legacy_x64.exe"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Release binaries in $DIST/:"
ls -lh "$DIST"/ 2>/dev/null | grep -v '^total' || echo "  (none)"
echo ""
