#!/bin/sh
# LabDesk installer for Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.sh | sudo sh
#
# Downloads the newest LabDesk release from GitHub, picks the package format
# that matches this distribution, and installs it. Re-running the script
# upgrades an existing installation in place.
#
# To point the client at a server as part of the install, set any of these
# before running it:
#
#   LABDESK_HOST    ID / rendezvous server
#   LABDESK_RELAY   relay server
#   LABDESK_API     API server
#   LABDESK_KEY     server public key
#
#   curl -fsSL .../install.sh | sudo LABDESK_HOST=id.example.com LABDESK_KEY=abc sh
#
# Nothing is written to those settings unless you supply a value.

set -eu

REPO=tfdan-cts/LabDesk
API="https://api.github.com/repos/$REPO/releases/latest"

die() { echo "labdesk: $*" >&2; exit 1; }
info() { echo "labdesk: $*"; }

[ "$(id -u)" = "0" ] || die "must run as root. Pipe to 'sudo sh' instead of 'sh'."
command -v curl >/dev/null 2>&1 || die "curl is required but not installed."

case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "unsupported architecture '$(uname -m)'. LabDesk ships x86_64 and aarch64 packages." ;;
esac

# Each entry is the tool that must exist, the pattern matching its package in
# the release, and the command that installs a local file with that tool.
if command -v apt-get >/dev/null 2>&1; then
    manager=apt
    pattern="rustdesk-.*-${arch}\.deb"
elif command -v zypper >/dev/null 2>&1; then
    manager=zypper
    pattern="rustdesk-.*-${arch}-suse\.rpm"
elif command -v dnf >/dev/null 2>&1; then
    manager=dnf
    pattern="rustdesk-.*\.${arch}\.rpm"
elif command -v yum >/dev/null 2>&1; then
    manager=yum
    pattern="rustdesk-.*\.${arch}\.rpm"
elif command -v pacman >/dev/null 2>&1; then
    [ "$arch" = "x86_64" ] || die "LabDesk ships an Arch package for x86_64 only, not $arch."
    manager=pacman
    pattern="rustdesk-.*-${arch}\.pkg\.tar\.zst"
else
    die "no supported package manager found (looked for apt-get, zypper, dnf, yum, pacman)."
fi

info "installing for $arch using $manager"

# The asset names carry the upstream RustDesk version rather than the release
# tag, so the download URL has to come from the release metadata. Parsed with
# grep and sed because jq is not present on a stock image.
url=$(curl -fsSL "$API" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed 's/.*"\(https[^"]*\)"/\1/' \
    | grep -E "/${pattern}$" \
    | head -n 1) || true

[ -n "${url:-}" ] || die "no $manager package for $arch in the latest release. See https://github.com/$REPO/releases"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
pkg="$tmp/${url##*/}"

info "downloading ${url##*/}"
curl -fsSL --retry 3 -o "$pkg" "$url" || die "download failed: $url"

info "installing $(basename "$pkg")"
case "$manager" in
    apt) apt-get install -y "$pkg" ;;
    dnf) dnf install -y "$pkg" ;;
    yum) yum install -y "$pkg" ;;
    zypper) zypper --non-interactive install --allow-unsigned-rpm "$pkg" ;;
    pacman) pacman -U --noconfirm "$pkg" ;;
esac

command -v rustdesk >/dev/null 2>&1 || die "install finished but the rustdesk binary is not on PATH."

# The package enables and starts rustdesk.service itself. Setting an option
# talks to that service over IPC, so it has to be up first.
set_option() {
    [ -n "${2:-}" ] || return 0
    info "setting $1"
    rustdesk --option "$1" "$2" || die "could not set $1. Is rustdesk.service running?"
}

if [ -n "${LABDESK_HOST:-}${LABDESK_RELAY:-}${LABDESK_API:-}${LABDESK_KEY:-}" ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet rustdesk || systemctl start rustdesk || true
    fi
    set_option custom-rendezvous-server "${LABDESK_HOST:-}"
    set_option relay-server "${LABDESK_RELAY:-}"
    set_option api-server "${LABDESK_API:-}"
    set_option key "${LABDESK_KEY:-}"
fi

info "done. Launch LabDesk from your applications menu or run 'rustdesk'."
