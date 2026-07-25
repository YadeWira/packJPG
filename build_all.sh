#!/usr/bin/env bash
# build_all.sh — build all packJPG release targets from project root
#
# Targets:
#   Linux x64      (native, requires g++ or clang++)
#   Windows x64    (Windows 7 SP1+, requires x86_64-w64-mingw32-g++-posix)
#   Windows x86    (Windows 7 SP1+, requires i686-w64-mingw32-g++-posix)
#
# Single codebase (source/) covers both Windows archs down to Windows 7 —
# the former sourcelegacy/ (C++14, Win32-API-only) tree existed only to
# support Windows XP, which v5.0 dropped entirely; once the officially
# supported floor became Windows 7, source/'s C++17/std::filesystem code
# already worked there (Win32 APIs std::filesystem needs predate Windows 7
# by a wide margin), making the second codebase redundant.
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
# -static-libgcc -static-libstdc++: avoids requiring a minimum libstdc++.so.6
# version at runtime on the end user's machine — same portability class as
# the vendored static CharLS/libjxl (linuxlibs/) and the CI ubuntu-22.04 pin.
CFLAGS="-I. -O3 -Wall -funroll-loops -ffast-math -fomit-frame-pointer -std=c++17 -static-libgcc -static-libstdc++"
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

linuxlibs_link() {
    local d="linuxlibs/x86_64"
    echo "$d/libcharls.a $d/libjxl.a $d/libjxl_threads.a $d/libjxl_cms.a" \
         "$d/liblcms2.a $d/libhwy.a $d/libbrotlienc.a $d/libbrotlidec.a $d/libbrotlicommon.a"
}

# JPEG-LS support: prefer the vendored static libs under source/linuxlibs/
# (zero runtime dependency — a dynamically-linked binary's Depends can drift
# out of sync with whatever libjxl/libcharls .so the build machine happens
# to have, which is exactly what broke the v5.0a .deb: built against
# libjxl.so.0.7 on CI, crashed on any system without that exact SONAME).
# Falls back to a dynamic-link probe against system libcharls-dev/libjxl-dev
# if the vendored libs aren't present (e.g. a stripped-down fork).
# JLS_LIBS must stay after $SRC/$JLS_SRC on the command line (linker order).
JLS_SRC=""
JLS_DEFINE=""
JLS_LIBS=""
if [ -f "$SRC_DIR/linuxlibs/x86_64/libcharls.a" ]; then
    JLS_SRC="jpegls.cpp"
    JLS_DEFINE="-DHAVE_JPEGLS -DCHARLS_STATIC -DJXL_STATIC_DEFINE -Iwinlibs/include"
    JLS_LIBS="$(linuxlibs_link)"
    ok "JPEG-LS support detected (vendored static libs, no runtime deps)"
elif echo 'int main(){}' | $CXX $CFLAGS -x c++ -lcharls -ljxl -ljxl_threads -o /dev/null - 2>/dev/null; then
    JLS_SRC="jpegls.cpp"
    JLS_DEFINE="-DHAVE_JPEGLS"
    JLS_LIBS="-lcharls -ljxl -ljxl_threads"
    ok "JPEG-LS support detected (libcharls-dev + libjxl-dev found, dynamic)"
else
    skip "JPEG-LS support disabled (no vendored libs, libcharls-dev/libjxl-dev not found)"
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

# ─── Windows JPEG-LS (vendored) ─────────────────────────────────────────────
# No mingw packages of CharLS/libjxl exist, so the static libs are vendored
# under source/winlibs/ instead of built per-release. See
# source/winlibs/README.md for the reproducible cross-compile recipe.
WINJLS_DEFS="-DHAVE_JPEGLS -DCHARLS_STATIC -DJXL_STATIC_DEFINE -Iwinlibs/include"
winlibs_link() {
    # $1 = arch dir (x86_64 or i686)
    local d="winlibs/$1"
    echo "$d/libcharls.a $d/libjxl.a $d/libjxl_threads.a $d/libjxl_cms.a" \
         "$d/liblcms2.a $d/libhwy.a $d/libbrotlienc.a $d/libbrotlidec.a $d/libbrotlicommon.a"
}

# ─── Windows x64 ─────────────────────────────────────────────────────────────

echo ""
echo "==> Windows x64"
# -posix (not the plain/win32-model alias): the win32 thread model doesn't
# implement std::async/std::future at all on some distros' mingw-w64
# packaging (compile-time "declared but never defined" errors) — found
# pinning CI to ubuntu-22.04, where the default alias differs from what
# happened to work on other distros. -posix is winpthread-backed and
# unambiguously supports the full <thread>/<future> API on any distro.
WIN64="x86_64-w64-mingw32-g++-posix"
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

    WIN64_JLS=""
    WIN64_JLS_SRC=""
    WIN64_JLS_LIBS=""
    if [ -f "$SRC_DIR/winlibs/x86_64/libcharls.a" ]; then
        WIN64_JLS="$WINJLS_DEFS"
        WIN64_JLS_SRC="jpegls.cpp"
        WIN64_JLS_LIBS="$(winlibs_link x86_64)"
        ok "Windows x64 JPEG-LS: winlibs/x86_64 found"
    else
        skip "Windows x64 JPEG-LS: source/winlibs/x86_64 not found"
    fi

    (cd "$SRC_DIR" && $WIN64 $CFLAGS $WIN64_JLS \
        -o "../$DIST/packJPG_win_x64.exe" \
        $SRC $WIN64_JLS_SRC $ICONS64 $WIN64_JLS_LIBS \
        -static -static-libgcc -static-libstdc++ \
        && x86_64-w64-mingw32-strip --strip-unneeded "../$DIST/packJPG_win_x64.exe")
    [ -f "$SRC_DIR/icons_x64.o" ] && rm -f "$SRC_DIR/icons_x64.o"
    ok "dist/packJPG_win_x64.exe"
fi

# ─── Windows x86 ─────────────────────────────────────────────────────────────

echo ""
echo "==> Windows x86"
WIN86="i686-w64-mingw32-g++-posix"
WINDRES86="i686-w64-mingw32-windres"
if ! command -v "$WIN86" &>/dev/null; then
    skip "$WIN86 not found — skipping Windows x86"
    skip "Install with: sudo apt install mingw-w64"
else
    ICONS86=""
    if command -v "$WINDRES86" &>/dev/null; then
        (cd "$SRC_DIR" && $WINDRES86 -O coff icons.rc -o icons_x86.o \
            && echo "    [OK] icons compiled for x86" \
            || echo "    [!!] icon compilation failed — binary will have no icon")
        [ -f "$SRC_DIR/icons_x86.o" ] && ICONS86="icons_x86.o"
    else
        echo "    [!!] $WINDRES86 not found — binary will have no icon"
    fi

    WIN86_JLS=""
    WIN86_JLS_SRC=""
    WIN86_JLS_LIBS=""
    if [ -f "$SRC_DIR/winlibs/i686/libcharls.a" ]; then
        WIN86_JLS="$WINJLS_DEFS"
        WIN86_JLS_SRC="jpegls.cpp"
        WIN86_JLS_LIBS="$(winlibs_link i686)"
        ok "Windows x86 JPEG-LS: winlibs/i686 found"
    else
        skip "Windows x86 JPEG-LS: source/winlibs/i686 not found"
    fi

    (cd "$SRC_DIR" && $WIN86 $CFLAGS $WIN86_JLS \
        -o "../$DIST/packJPG_win_x86.exe" \
        $SRC $WIN86_JLS_SRC $ICONS86 $WIN86_JLS_LIBS \
        -static -static-libgcc -static-libstdc++ \
        && i686-w64-mingw32-strip --strip-unneeded "../$DIST/packJPG_win_x86.exe")
    [ -f "$SRC_DIR/icons_x86.o" ] && rm -f "$SRC_DIR/icons_x86.o"
    ok "dist/packJPG_win_x86.exe"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Release binaries in $DIST/:"
ls -lh "$DIST"/ 2>/dev/null | grep -v '^total' || echo "  (none)"
echo ""
