#!/usr/bin/env bash
# build_pkg.sh — build packJPG packages for Linux x64
#
# Usage:
#   ./build_pkg.sh                         # build all available formats
#   ./build_pkg.sh --deb --rpm --snap      # selected formats only
#
# Supported formats:
#   --tar      .tar.gz tarball        (no extra tools needed)
#   --deb      Debian/Ubuntu          (requires dpkg-deb)
#   --rpm      Fedora/RHEL/openSUSE   (requires rpmbuild)
#   --appimage AppImage               (requires appimagetool; ImageMagick for icon)
#   --snap     Snap                   (requires snap)
#
# Output: dist/packjpg-<version>-linux-x64.tar.gz
#         dist/packjpg_<version>_amd64.deb
#         dist/packjpg-<version>-1.x86_64.rpm
#         dist/packjpg-<version>-x86_64.AppImage
#         dist/packjpg_<version>_amd64.snap

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

BUILD_TAR=false
BUILD_DEB=false
BUILD_RPM=false
BUILD_APPIMAGE=false
BUILD_SNAP=false
ANY_EXPLICIT=false

for arg in "$@"; do
    case "$arg" in
        --tar)      BUILD_TAR=true;      ANY_EXPLICIT=true ;;
        --deb)      BUILD_DEB=true;      ANY_EXPLICIT=true ;;
        --rpm)      BUILD_RPM=true;      ANY_EXPLICIT=true ;;
        --appimage) BUILD_APPIMAGE=true; ANY_EXPLICIT=true ;;
        --snap)     BUILD_SNAP=true;     ANY_EXPLICIT=true ;;
        *) fail "Unknown argument: $arg" ;;
    esac
done

# No flags = build all
if ! $ANY_EXPLICIT; then
    BUILD_TAR=true
    BUILD_DEB=true
    BUILD_RPM=true
    BUILD_APPIMAGE=true
    BUILD_SNAP=true
fi

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

# ─── .tar.gz ─────────────────────────────────────────────────────────────────

if $BUILD_TAR; then
    echo ""
    echo "==> Building .tar.gz"

    TAR_NAME="${PKG}-${VERSION}-linux-x64"
    STAGING="$DIST/$TAR_NAME"

    rm -rf "$STAGING"
    install -d "$STAGING"
    install -m 755 "$BINARY" "$STAGING/packjpg"
    install -m 644 LICENSE  "$STAGING/LICENSE"

    tar -C "$DIST" -czf "$DIST/${TAR_NAME}.tar.gz" "$TAR_NAME"
    rm -rf "$STAGING"
    ok "dist/${TAR_NAME}.tar.gz  ($(du -h "$DIST/${TAR_NAME}.tar.gz" | cut -f1))"
fi

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

# ─── AppImage ────────────────────────────────────────────────────────────────

if $BUILD_APPIMAGE; then
    echo ""
    echo "==> Building AppImage"

    if ! command -v appimagetool &>/dev/null; then
        skip "appimagetool not found — skipping AppImage"
        skip "  Download: https://github.com/AppImage/appimagetool/releases"
        skip "  Then: chmod +x appimagetool-x86_64.AppImage && sudo mv it to /usr/local/bin/appimagetool"
    else
        APPDIR="$DIST/packjpg.AppDir"
        rm -rf "$APPDIR"
        install -d "$APPDIR/usr/bin"

        install -m 755 "$BINARY" "$APPDIR/usr/bin/packjpg"

        # AppRun — entry point
        cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/usr/bin/packjpg" "$@"
EOF
        chmod +x "$APPDIR/AppRun"

        # .desktop file (required by AppImage spec)
        cat > "$APPDIR/packjpg.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=packJPG
Exec=packjpg
Icon=packjpg
Comment=Lossless JPEG compressor
Categories=Utility;
Terminal=true
NoDisplay=true
EOF

        # Icon — convert app_icon.ico to PNG if ImageMagick is available
        if command -v convert &>/dev/null && [[ -f "$SRC_DIR/app_icon.ico" ]]; then
            convert "$SRC_DIR/app_icon.ico[0]" "$APPDIR/packjpg.png" 2>/dev/null \
                && echo "    [OK] icon converted from app_icon.ico" \
                || { install -m 644 /dev/null "$APPDIR/packjpg.png"; echo "    [!!] icon conversion failed — using empty placeholder"; }
        else
            # Minimal 1x1 transparent PNG as fallback (AppImage requires an icon file)
            printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' \
                > "$APPDIR/packjpg.png"
            [[ ! -f "$SRC_DIR/app_icon.ico" ]] \
                && echo "    [--] app_icon.ico not found — using placeholder icon" \
                || echo "    [--] ImageMagick not found — using placeholder icon (sudo apt install imagemagick)"
        fi

        APPIMAGE_OUT="$DIST/${PKG}-${VERSION}-x86_64.AppImage"
        ARCH=x86_64 appimagetool "$APPDIR" "$APPIMAGE_OUT" 2>&1 | grep -v '^squashfs'
        rm -rf "$APPDIR"
        ok "$(basename "$APPIMAGE_OUT")  ($(du -h "$APPIMAGE_OUT" | cut -f1))"
    fi
fi

# ─── Snap ────────────────────────────────────────────────────────────────────

if $BUILD_SNAP; then
    echo ""
    echo "==> Building Snap"

    if ! command -v snap &>/dev/null; then
        skip "snap not found — skipping Snap  (sudo apt install snapd)"
    else
        SNAP_DIR="$DIST/snap-staging"
        rm -rf "$SNAP_DIR"
        install -d "$SNAP_DIR/meta"
        install -d "$SNAP_DIR/usr/bin"

        install -m 755 "$BINARY" "$SNAP_DIR/usr/bin/packjpg"

        cat > "$SNAP_DIR/meta/snap.yaml" <<EOF
name: $PKG
version: "$VERSION"
summary: Lossless JPEG compressor
description: |
  packJPG compresses JPEG files to the PJG format for lossless archival,
  achieving better compression than standard JPEG storage. Supports
  single-file parallel compression (-sfth) and batch multi-threading (-th).
confinement: strict
grade: stable
base: core22

apps:
  packjpg:
    command: usr/bin/packjpg
    plugs:
      - home
      - removable-media
EOF

        SNAP_OUT="$DIST/${PKG}_${VERSION}_amd64.snap"
        snap pack "$SNAP_DIR" --filename "$SNAP_OUT"
        rm -rf "$SNAP_DIR"
        ok "$(basename "$SNAP_OUT")  ($(du -h "$SNAP_OUT" | cut -f1))"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "Packages in $DIST/:"
find "$DIST" -maxdepth 1 \( -name "*.tar.gz" -o -name "*.deb" -o -name "*.rpm" \
    -o -name "*.AppImage" -o -name "*.snap" \) \
    | sort | while read -r f; do printf "  %-45s %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"; done
echo ""
