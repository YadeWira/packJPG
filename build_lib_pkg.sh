#!/usr/bin/env bash
# build_lib_pkg.sh — build packJPG library/SDK archives for embedders
#
# Produces the 3 archives previously built ad-hoc and uploaded by hand to
# GitHub Releases (never scripted before v5.0 — this fixes that gap):
#   dist/packJPG-<ver>-linux-x64-lib.tar.gz   packJPGlib.a + libpackJPG.so
#   dist/packJPG-<ver>-win64-lib.zip          packJPG.dll + libpackJPG.a
#   dist/packJPG-<ver>-win32-lib.zip          packJPG.dll + libpackJPG.a
#
# Requires mingw-w64 (posix thread model variant) for the Windows archives;
# skips them with a warning if not found. Linux archive only needs the
# native compiler already required for build_all.sh.

set -euo pipefail
cd "$(dirname "$0")"

APP=$(grep -oP 'appversion\s*=\s*\K\d+' source/packjpg.cpp | head -1)
SUB=$(grep -oP 'subversion\s*=\s*"\K[^"]*' source/packjpg.cpp | head -1)
VERSION="${APP:0:1}.${APP:1}${SUB}"

DIST="dist"
mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
skip() { echo "[--]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

JLS_NOTE=""
if echo 'int main(){}' | ${CXX:-clang++} -x c++ -lcharls -ljxl -ljxl_threads -o /dev/null - 2>/dev/null; then
    JLS_NOTE=" + JPEG-LS (requires libcharls2, libjxl0.11 at runtime)"
fi

# ─── Linux x64 ───────────────────────────────────────────────────────────────

echo ""
echo "==> Linux x64 library"
(cd source && make clean >/dev/null && make lib >/dev/null && make so >/dev/null)

LINUX_STAGE="$DIST/packJPG-${VERSION}-linux-x64-lib"
rm -rf "$LINUX_STAGE"
install -d "$LINUX_STAGE"
install -m 644 source/packJPGlib.a   "$LINUX_STAGE/"
install -m 755 source/libpackJPG.so  "$LINUX_STAGE/"
install -m 644 source/packjpglib.h   "$LINUX_STAGE/"

cat > "$LINUX_STAGE/README.txt" <<EOF
packJPG v${VERSION} — Linux library/SDK (x64)
========================================
Embed packJPG (lossless JPEG <-> PJG) in your program. C-linkage API,
multithreading ON by default${JLS_NOTE}.

Files
  libpackJPG.so   shared object (exports only the pjglib_* API)
  packJPGlib.a    static library
  packjpglib.h    API header (C / C++)

Link:  cc your.c -lpackJPG            (shared, .so on the loader path)
       cc your.c packJPGlib.a -lstdc++ -lpthread   (static)

Quick API
  pjglib_convert_file2file(in, out, msg)
  pjglib_convert_stream2mem(&out, &out_size, msg)     // out malloc'd
  pjglib_convert_batch(ops, n_ops, msg)               // parallel N files
  pjglib_set_intra/inter_file_threads(n), pjglib_suggest_batch_threads()
  pjglib_set_max_output_size(bytes)   // decompression-bomb guard; 0 = off

Full reference + example: README "Library / DLL API" at
https://github.com/YadeWira/packJPG
EOF

tar -C "$DIST" -czf "$DIST/packJPG-${VERSION}-linux-x64-lib.tar.gz" "packJPG-${VERSION}-linux-x64-lib"
rm -rf "$LINUX_STAGE"
(cd source && rm -f packJPGlib.a libpackJPG.so && make clean >/dev/null)
ok "dist/packJPG-${VERSION}-linux-x64-lib.tar.gz"

# ─── Windows (win64 / win32) ──────────────────────────────────────────────────

build_win_lib() {
    local ARCH="$1" CXX_POSIX="$2" WINLIBS_DLL_DIR="$3"
    echo ""
    echo "==> Windows $ARCH library"

    if ! command -v "$CXX_POSIX" &>/dev/null; then
        skip "$CXX_POSIX not found — skipping win-$ARCH library (needs posix thread model)"
        return
    fi

    local WIN_JLS_NOTE=""
    [ -f "source/winlibs-dll/$WINLIBS_DLL_DIR/libcharls.a" ] && \
        WIN_JLS_NOTE=" + JPEG-LS (vendored static libs, no runtime deps)"

    (cd source && make clean >/dev/null \
        && make dll CXX="$CXX_POSIX" >/dev/null)

    local STAGE="$DIST/packJPG-${VERSION}-${ARCH}-lib"
    rm -rf "$STAGE"
    install -d "$STAGE"
    install -m 755 source/packJPG.dll    "$STAGE/"
    install -m 644 source/libpackJPG.a   "$STAGE/"
    install -m 644 source/packJPG.def    "$STAGE/"
    install -m 644 source/packjpgdll.h   "$STAGE/"
    install -m 644 source/packjpglib.h   "$STAGE/"

    local MACHINE="x64"; [ "$ARCH" = "win32" ] && MACHINE="x86"

    cat > "$STAGE/README.txt" <<EOF
packJPG v${VERSION} — Windows library/SDK (${ARCH})
=============================================
Embed packJPG (lossless JPEG <-> PJG) in your program. C-linkage API,
multithreading ON by default${WIN_JLS_NOTE}.
On-disk .pjg format unchanged since v4.0b.

Files
  packJPG.dll     self-contained DLL (depends only on KERNEL32 + msvcrt)
  libpackJPG.a    import library (MinGW / Clang)
  packJPG.def     module-def for MSVC:  lib /def:packJPG.def /machine:${MACHINE}
  packjpglib.h    API header (MinGW/Clang/C)
  packjpgdll.h    API header for MSVC (__declspec(dllimport))

Quick API
  pjglib_convert_file2file(in, out, msg)
  pjglib_convert_stream2mem(&out, &out_size, msg)     // out malloc'd
  pjglib_convert_batch(ops, n_ops, msg)               // parallel N files
  pjglib_set_intra/inter_file_threads(n), pjglib_suggest_batch_threads()
  pjglib_set_max_output_size(bytes)   // decompression-bomb guard; 0 = off

Untrusted .pjg input: set a ceiling once at startup, e.g.
  pjglib_set_max_output_size(64u*1024*1024);   // refuse >64 MB reconstructions

Full reference + example: README "Library / DLL API" at
https://github.com/YadeWira/packJPG
EOF

    (cd "$DIST" && zip -q -r "packJPG-${VERSION}-${ARCH}-lib.zip" "packJPG-${VERSION}-${ARCH}-lib")
    rm -rf "$STAGE"
    (cd source && rm -f packJPG.dll libpackJPG.a && make clean >/dev/null)
    ok "dist/packJPG-${VERSION}-${ARCH}-lib.zip"
}

build_win_lib win64 x86_64-w64-mingw32-g++-posix x86_64
build_win_lib win32 i686-w64-mingw32-g++-posix   i686

echo ""
echo "Library archives in $DIST/:"
ls -lh "$DIST"/*-lib.* 2>/dev/null | grep -v '^total' || echo "  (none)"
