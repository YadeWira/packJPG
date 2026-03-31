#!/usr/bin/env bash
# build_all.sh — builds packJPG for Linux x64, Windows x86, and Windows x64
#
# Requirements: clang++ (or g++), mingw-w64
#   Ubuntu/Debian : sudo apt install mingw-w64
#   Arch          : sudo pacman -S mingw-w64-gcc
#   macOS         : brew install mingw-w64

set -e
cd "$(dirname "$0")"

SRC="aricoder.cpp bitops.cpp packjpg.cpp"
CFLAGS="-I. -O3 -Wall -funroll-loops -ffast-math -fomit-frame-pointer -std=c++17"
CFLAGS_NATIVE="$CFLAGS -march=native"  # CPU-specific, not for distribution
OUT="bin"

mkdir -p "$OUT"

ok()   { echo "[OK]  $*"; }
fail() { echo "[!!]  $*"; exit 1; }

# --- Linux x64 ---------------------------------------------------------------

echo ""
echo "==> Linux x64"
if command -v clang++ &>/dev/null; then
    CXX="clang++"
elif command -v g++ &>/dev/null; then
    CXX="g++"
else
    fail "No C++ compiler found (clang++ or g++ required)"
fi

$CXX $CFLAGS -DUNIX \
    -o "$OUT/packJPG_linux_x64" \
    $SRC \
    && strip --strip-unneeded "$OUT/packJPG_linux_x64" \
    && ok "bin/packJPG_linux_x64"

# native build (optimized for this machine only, not for distribution)
$CXX $CFLAGS_NATIVE -DUNIX \
    -o "$OUT/packJPG_linux_x64_native" \
    $SRC \
    && ok "bin/packJPG_linux_x64_native (native, do not distribute)"

# --- Windows x64 -------------------------------------------------------------

echo ""
echo "==> Windows x64"
WIN64="x86_64-w64-mingw32-g++"
WINDRES64="x86_64-w64-mingw32-windres"
if ! command -v $WIN64 &>/dev/null; then
    echo "    [--] $WIN64 not found, skipping Windows x64"
    echo "         Install with: sudo apt install mingw-w64"
else
    ICONS64=""
    if command -v $WINDRES64 &>/dev/null; then
        $WINDRES64 -O coff icons.rc -o icons_x64.o \
            && ICONS64="icons_x64.o" \
            && echo "    [OK] icons compiled for x64" \
            || echo "    [!!] icon compilation failed — binary will have no icon"
    else
        echo "    [!!] $WINDRES64 not found — binary will have no icon"
    fi

    $WIN64 $CFLAGS \
        -o "$OUT/packJPG_win_x64.exe" \
        $SRC $ICONS64 \
        -static -static-libgcc -static-libstdc++ \
    && x86_64-w64-mingw32-strip --strip-unneeded "$OUT/packJPG_win_x64.exe" \
        && ok "bin/packJPG_win_x64.exe"

    [ -f icons_x64.o ] && rm -f icons_x64.o
fi

# --- Windows x86 (32-bit) ----------------------------------------------------

echo ""
echo "==> Windows x86 (32-bit)"
WIN32="i686-w64-mingw32-g++"
WINDRES32="i686-w64-mingw32-windres"
if ! command -v $WIN32 &>/dev/null; then
    echo "    [--] $WIN32 not found, skipping Windows x86"
    echo "         Install with: sudo apt install mingw-w64"
else
    ICONS32=""
    if command -v $WINDRES32 &>/dev/null; then
        $WINDRES32 -O coff icons.rc -o icons_x86.o \
            && ICONS32="icons_x86.o" \
            && echo "    [OK] icons compiled for x86" \
            || echo "    [!!] icon compilation failed — binary will have no icon"
    else
        echo "    [!!] $WINDRES32 not found — binary will have no icon"
    fi

    $WIN32 $CFLAGS \
        -o "$OUT/packJPG_win_x86.exe" \
        $SRC $ICONS32 \
        -static -static-libgcc -static-libstdc++ \
    && i686-w64-mingw32-strip --strip-unneeded "$OUT/packJPG_win_x86.exe" \
        && ok "bin/packJPG_win_x86.exe"

    [ -f icons_x86.o ] && rm -f icons_x86.o
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "Output binaries:"
ls -lh "$OUT"/ 2>/dev/null || echo "(none)"