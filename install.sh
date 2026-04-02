#!/usr/bin/env bash
# install.sh — install packJPG
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/YadeWira/packJPG/master/install.sh | bash
#
# On Debian/Ubuntu this sets up the apt repository so future updates
# arrive via 'apt upgrade'. On other distros it installs from the
# latest GitHub release directly.
#
# Options:
#   --apt-only    set up apt repo and exit without fallback
#   --prefix=DIR  install prefix for tar fallback (default: /usr/local)

set -euo pipefail

REPO="YadeWira/packJPG"
APT_REPO="https://yadewira.github.io/packJPG"
GPG_KEY_URL="https://raw.githubusercontent.com/YadeWira/packJPG/master/packjpg.gpg"
PREFIX="/usr/local"
APT_ONLY=false

# ─── Parse args ──────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --apt-only)  APT_ONLY=true ;;
        --prefix=*)  PREFIX="${arg#--prefix=}" ;;
        --prefix)    shift; PREFIX="$1" ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ─── Checks ──────────────────────────────────────────────────────────────────

need() { command -v "$1" &>/dev/null || { echo "error: '$1' is required but not found" >&2; exit 1; }; }
need curl

OS="$(uname -s)"
ARCH="$(uname -m)"
[[ "$OS" == "Linux" ]]    || { echo "error: unsupported OS '$OS' (only Linux is supported)" >&2; exit 1; }
[[ "$ARCH" == "x86_64" ]] || { echo "error: unsupported arch '$ARCH' (only x86_64 is supported)" >&2; exit 1; }

SUDO=""
[[ "$EUID" -ne 0 ]] && command -v sudo &>/dev/null && SUDO="sudo"

# ─── apt path (Debian/Ubuntu) ────────────────────────────────────────────────

if command -v apt &>/dev/null; then
    echo "Setting up packJPG apt repository ..."

    # Add GPG key
    curl -fsSL "$GPG_KEY_URL" | $SUDO tee /etc/apt/trusted.gpg.d/packjpg.asc > /dev/null

    # Add sources entry
    echo "deb $APT_REPO stable main" \
        | $SUDO tee /etc/apt/sources.list.d/packjpg.list > /dev/null

    $SUDO apt-get update -qq
    $SUDO apt-get install -y packjpg

    echo ""
    echo "packJPG installed via apt. Future updates will arrive via 'apt upgrade'."
    exit 0
fi

$APT_ONLY && { echo "error: apt not found" >&2; exit 1; }

# ─── Fetch latest release info ───────────────────────────────────────────────

echo "Fetching latest release from github.com/$REPO ..."

API="https://api.github.com/repos/$REPO/releases/latest"
RELEASE_JSON="$(curl -fsSL "$API")"
VERSION="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')"

if [[ -z "$VERSION" ]]; then
    echo "error: could not determine latest release version" >&2
    exit 1
fi

echo "Latest version: $VERSION"

# ─── Choose package format ───────────────────────────────────────────────────

# Prefer native package manager format so the system tracks the install
DEB_URL=""
RPM_URL=""
TAR_URL=""

while IFS= read -r url; do
    case "$url" in
        *.deb)    DEB_URL="$url" ;;
        *.rpm)    RPM_URL="$url" ;;
        *.tar.gz) TAR_URL="$url" ;;
    esac
done < <(echo "$RELEASE_JSON" | grep '"browser_download_url"' | sed 's/.*"browser_download_url": *"\(.*\)".*/\1/')

INSTALL_METHOD=""
DOWNLOAD_URL=""

if command -v apt &>/dev/null && [[ -n "$DEB_URL" ]]; then
    INSTALL_METHOD="deb"
    DOWNLOAD_URL="$DEB_URL"
elif command -v dnf &>/dev/null && [[ -n "$RPM_URL" ]]; then
    INSTALL_METHOD="rpm-dnf"
    DOWNLOAD_URL="$RPM_URL"
elif command -v yum &>/dev/null && [[ -n "$RPM_URL" ]]; then
    INSTALL_METHOD="rpm-yum"
    DOWNLOAD_URL="$RPM_URL"
elif command -v rpm &>/dev/null && [[ -n "$RPM_URL" ]]; then
    INSTALL_METHOD="rpm"
    DOWNLOAD_URL="$RPM_URL"
elif [[ -n "$TAR_URL" ]]; then
    INSTALL_METHOD="tar"
    DOWNLOAD_URL="$TAR_URL"
else
    echo "error: no compatible package found in release assets" >&2
    exit 1
fi

# ─── Download ────────────────────────────────────────────────────────────────

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FILENAME="$(basename "$DOWNLOAD_URL")"
DEST="$TMPDIR/$FILENAME"

echo "Downloading $FILENAME ..."
curl -fsSL --progress-bar -o "$DEST" "$DOWNLOAD_URL"

# ─── Install ─────────────────────────────────────────────────────────────────

case "$INSTALL_METHOD" in
    deb)
        echo "Installing via dpkg ..."
        $SUDO dpkg -i "$DEST"
        ;;
    rpm-dnf)
        echo "Installing via dnf ..."
        $SUDO dnf install -y "$DEST"
        ;;
    rpm-yum)
        echo "Installing via yum ..."
        $SUDO yum install -y "$DEST"
        ;;
    rpm)
        echo "Installing via rpm ..."
        $SUDO rpm -U "$DEST"
        ;;
    tar)
        echo "Installing to $PREFIX/bin ..."
        $SUDO install -d "$PREFIX/bin"
        tar -C "$TMPDIR" -xzf "$DEST"
        $SUDO install -m 755 "$TMPDIR"/packjpg*/packjpg "$PREFIX/bin/packjpg"
        ;;
esac

# ─── Verify ──────────────────────────────────────────────────────────────────

if command -v packjpg &>/dev/null; then
    echo ""
    echo "packJPG installed successfully:"
    packjpg --version 2>/dev/null || packjpg -v 2>/dev/null || true
    echo "  $(command -v packjpg)"
else
    echo ""
    echo "Installed. You may need to add $PREFIX/bin to your PATH."
fi
