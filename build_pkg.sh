#!/usr/bin/env bash
# build_pkg.sh — build packJPG packages for Linux x64
#
# Usage:
#   ./build_pkg.sh            # build all available formats
#   ./build_pkg.sh --deb      # .deb only
#   ./build_pkg.sh --rpm      # .rpm only
#
# Requires: g++ or clang++
#   .deb: dpkg-deb   (sudo apt install dpkg)
#   .rpm: rpmbuild   (sudo apt install rpm  /  sudo dnf install rpm-build)
#
# Output: dist/packjpg_<version>_amd64.deb
#         dist/packjpg-<version>-1.x86_64.rpm

set -euo pipefail
cd "$(dirname "$0")"

# ─── Version (keep in sync with packjpg.cpp appversion/subversion) ───────────
VERSION="3.1"
PKG="packjpg"

SRC_DIR="source"
SRC="aricoder.cpp bitops.cpp packjpg.cpp"
CFLAGS="-I. -O3 -Wall -funroll-loops -ffast-math -fomit-frame-pointer -std=c++17 -DUNIX"
DIST="dist"
BINARY="$DIST/packJPG_linux_x64"

mkdir -p "$DIST"

ok()   { echo "[OK]  $*"; }
skip() { echo "[--]  $*"; }
fail() { echo "[!!]  $*" >&2; exit 1; }

# ─── Parse args ──────────────────────────────────────────────────────────────

BUILD_DEB=true
BUILD_RPM=true

for arg in "$@"; do
    case "$arg" in
        --deb) BUILD_DEB=true;  BUILD_RPM=false ;;
        --rpm) BUILD_DEB=false; BUILD_RPM=true  ;;
        *) fail "Unknown argument: $arg" ;;
    esac
done

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
    -o "../$BINARY" \
    $SRC \
    && strip --strip-unneeded "../$BINARY")
ok "$BINARY"

# ─── .deb ────────────────────────────────────────────────────────────────────

if $BUILD_DEB; then
    echo ""
    echo "==> Building .deb"

    if ! command -v dpkg-deb &>/dev/null; then
        skip "dpkg-deb not found — skipping .deb  (sudo apt install dpkg)"
    else
        DEB_NAME="${PKG}_${VERSION}_amd64"
        STAGING="$DIST/${DEB_NAME}"

        rm -rf "$STAGING"
        install -d "$STAGING/usr/bin"
        install -d "$STAGING/DEBIAN"
        install -m 755 "$BINARY" "$STAGING/usr/bin/packjpg"

        INSTALLED_SIZE=$(du -sk "$STAGING/usr" | cut -f1)

        cat > "$STAGING/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: amd64
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
    fi
fi

# ─── .rpm ────────────────────────────────────────────────────────────────────

if $BUILD_RPM; then
    echo ""
    echo "==> Building .rpm"

    if ! command -v rpmbuild &>/dev/null; then
        skip "rpmbuild not found — skipping .rpm"
        skip "  Debian/Ubuntu : sudo apt install rpm"
        skip "  Fedora/RHEL   : sudo dnf install rpm-build"
    else
        RPM_ROOT="$DIST/rpmbuild"
        rm -rf "$RPM_ROOT"
        mkdir -p "$RPM_ROOT"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

        # Copy binary into a source tree rpmbuild can install from
        install -Dm 755 "$BINARY" "$RPM_ROOT/BUILD/usr/bin/packjpg"

        cat > "$RPM_ROOT/SPECS/${PKG}.spec" <<EOF
Name:           $PKG
Version:        $VERSION
Release:        1
Summary:        Lossless JPEG compressor
License:        MIT
URL:            https://github.com/YadeWira/packJPG

%description
packJPG compresses JPEG files to the PJG format for lossless archival,
achieving better compression than standard JPEG storage. Supports
single-file parallel compression (-sfth) and batch multi-threading (-th).

%install
cp -a %{_builddir}/usr %{buildroot}/

%files
%{_bindir}/packjpg

%changelog
* $(date '+%a %b %d %Y') Yade Bravo <https://github.com/YadeWira/packJPG> - ${VERSION}-1
- Release ${VERSION}
EOF

        rpmbuild --define "_topdir $(pwd)/$RPM_ROOT" \
                 --define "_build_id_links none" \
                 --buildroot "$(pwd)/$RPM_ROOT/BUILDROOT" \
                 -bb "$RPM_ROOT/SPECS/${PKG}.spec" 2>&1 | grep -v '^Processing files'

        RPM_FILE=$(find "$RPM_ROOT/RPMS" -name "*.rpm" | head -1)
        if [[ -n "$RPM_FILE" ]]; then
            cp "$RPM_FILE" "$DIST/"
            DEST="$DIST/$(basename "$RPM_FILE")"
            rm -rf "$RPM_ROOT"
            ok "$(basename "$DEST")  ($(du -h "$DEST" | cut -f1))"
        else
            rm -rf "$RPM_ROOT"
            fail "rpmbuild completed but no .rpm found"
        fi
    fi
fi

echo ""
