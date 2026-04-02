#!/usr/bin/env bash
# build_deb.sh — build a .deb package for packJPG (Linux x64)
#
# Requires: dpkg-deb, g++ or clang++
# Output:   dist/packjpg_<version>_amd64.deb

set -euo pipefail
cd "$(dirname "$0")"

# ─── Version (keep in sync with packjpg.cpp appversion/subversion) ───────────
VERSION="3.1"
ARCH="amd64"
PKG="packjpg"
DEB_NAME="${PKG}_${VERSION}_${ARCH}"

SRC_DIR="source"
SRC="aricoder.cpp bitops.cpp packjpg.cpp"
CFLAGS="-I. -O3 -Wall -funroll-loops -ffast-math -fomit-frame-pointer -std=c++17 -DUNIX"
DIST="dist"
STAGING="$DIST/${DEB_NAME}"

mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

# ─── Compiler ────────────────────────────────────────────────────────────────

if command -v clang++ &>/dev/null; then
    CXX="clang++"
elif command -v g++ &>/dev/null; then
    CXX="g++"
else
    fail "No C++ compiler found (clang++ or g++ required)"
fi

# ─── Build binary ────────────────────────────────────────────────────────────

echo ""
echo "==> Compiling packJPG (Linux x64)"

(cd "$SRC_DIR" && $CXX $CFLAGS \
    -o "../$DIST/packJPG_linux_x64" \
    $SRC \
    && strip --strip-unneeded "../$DIST/packJPG_linux_x64")
ok "dist/packJPG_linux_x64"

# ─── Build .deb staging area ─────────────────────────────────────────────────

echo ""
echo "==> Building .deb package"

rm -rf "$STAGING"
install -d "$STAGING/usr/bin"
install -d "$STAGING/DEBIAN"

install -m 755 "$DIST/packJPG_linux_x64" "$STAGING/usr/bin/packjpg"

INSTALLED_SIZE=$(du -sk "$STAGING/usr" | cut -f1)

cat > "$STAGING/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: Yade Bravo <https://github.com/YadeWira/packJPG>
Installed-Size: $INSTALLED_SIZE
Section: utils
Priority: optional
Description: Lossless JPEG compressor
 packJPG compresses JPEG files to the PJG format for lossless archival,
 achieving better compression than standard JPEG storage. Supports
 single-file parallel compression (-sfth) and batch multi-threading (-th).
EOF

dpkg-deb --build --root-owner-group "$STAGING" "$DIST/${DEB_NAME}.deb"

rm -rf "$STAGING"

ok "dist/${DEB_NAME}.deb  ($(du -h "$DIST/${DEB_NAME}.deb" | cut -f1))"
echo ""
