#!/bin/sh
# LabDesk installer for Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.sh | sudo sh
#
# Downloads the newest LabDesk release from GitHub, picks the package format
# that matches this distribution, and installs it. Re-running the script
# upgrades an existing installation in place.
#
# To point the client at a server as part of the install, set any of these:
#
#   LABDESK_HOST    ID / rendezvous server
#   LABDESK_RELAY   relay server
#   LABDESK_API     API server
#   LABDESK_KEY     server public key
#
# They must be set for the shell that sudo runs, so put them after sudo:
#
#   curl -fsSL .../install.sh | sudo LABDESK_HOST=id.example.com LABDESK_KEY=abc sh
#
# Setting them before curl instead does not work, because sudo does not pass
# the surrounding environment through by default. Any setting you leave out is
# left untouched.
#
# Trust model: the packages are downloaded over TLS from github.com and are not
# signed or checksummed by this project. A working TLS connection to GitHub is
# the whole of the trust chain. Read the script before piping it to root, as you
# should with any installer that works this way.
#
# Arch note: pacman's default SigLevel rejects unsigned local packages, so the
# pacman path may refuse to install. The script says so if that happens.

set -eu

REPO=tfdan-cts/LabDesk
API="https://api.github.com/repos/$REPO/releases/latest"

die() { echo "labdesk: $*" >&2; exit 1; }
info() { echo "labdesk: $*"; }
warn() { echo "labdesk: warning: $*" >&2; }

[ "$(id -u)" = "0" ] || die "must run as root. Pipe to 'sudo sh' instead of 'sh'."
command -v curl >/dev/null 2>&1 || die "curl is required but not installed."

case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "unsupported architecture '$(uname -m)'. LabDesk ships x86_64 and aarch64 packages." ;;
esac

if command -v apt-get >/dev/null 2>&1; then
    manager=apt
    pattern="rustdesk-[0-9][^/]*-${arch}\.deb"
elif command -v zypper >/dev/null 2>&1; then
    manager=zypper
    pattern="rustdesk-[0-9][^/]*\.${arch}-suse\.rpm"
elif command -v dnf >/dev/null 2>&1; then
    manager=dnf
    pattern="rustdesk-[0-9][^/]*\.${arch}\.rpm"
elif command -v yum >/dev/null 2>&1; then
    manager=yum
    pattern="rustdesk-[0-9][^/]*\.${arch}\.rpm"
elif command -v pacman >/dev/null 2>&1; then
    [ "$arch" = "x86_64" ] || die "LabDesk ships an Arch package for x86_64 only, not $arch."
    manager=pacman
    pattern="rustdesk-[0-9][^/]*-${arch}\.pkg\.tar\.zst"
else
    die "no supported package manager found (looked for apt-get, zypper, dnf, yum, pacman).
Install one of the .AppImage or .flatpak builds by hand instead:
  https://github.com/$REPO/releases/latest"
fi

info "installing for $arch using $manager"

tmp=$(mktemp -d)
# EXIT does the cleanup. INT and TERM only exit, which then fires EXIT: a
# handler that merely cleans up would delete the directory and let the script
# carry on with the package manager still reading from it.
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Fetch the release metadata to a file so that a transport or HTTP failure is
# reported as itself. Folding this into the pipeline below would turn a rate
# limit into "no package for your architecture", which sends people looking for
# a problem they do not have.
code=$(curl -sSL -w '%{http_code}' -o "$tmp/release.json" "$API" 2>"$tmp/curl.err") || {
    die "could not reach the GitHub API: $(cat "$tmp/curl.err")"
}
case "$code" in
    200) ;;
    403 | 429)
        die "GitHub rate-limited this address (HTTP $code). The API allows 60 unauthenticated
requests an hour per IP, so imaging several machines behind one address can hit it.
Wait and retry, or download the package by hand:
  https://github.com/$REPO/releases/latest" ;;
    *) die "the GitHub API returned HTTP $code. See https://github.com/$REPO/releases/latest" ;;
esac

# The asset names carry the upstream RustDesk version rather than the release
# tag, so the download URL has to come from the metadata. Parsed with grep and
# sed because jq is not present on a stock image.
url=$(grep -o '"browser_download_url": *"[^"]*"' "$tmp/release.json" \
    | sed 's/.*"\(https[^"]*\)"/\1/' \
    | grep -E "/${pattern}$" \
    | head -n 1) || true

[ -n "${url:-}" ] || die "the latest release has no $manager package for $arch.
See https://github.com/$REPO/releases/latest"

# The URL comes out of an API response, so check it points where it should
# before handing it to curl and the package manager as root. Release assets are
# always served from these two hosts.
case "$url" in
    "https://github.com/$REPO/releases/download/"*) ;;
    "https://objects.githubusercontent.com/"*) ;;
    *) die "refusing to install from an unexpected location:
  $url
Release assets should come from github.com/$REPO." ;;
esac

pkg="$tmp/${url##*/}"
info "downloading ${url##*/}"
curl -fsSL --retry 3 -o "$pkg" "$url" || die "download failed: $url"

info "installing $(basename "$pkg")"
case "$manager" in
    apt) apt-get install -y "$pkg" ;;
    dnf) dnf install -y "$pkg" ;;
    yum) yum install -y "$pkg" ;;
    zypper) zypper --non-interactive install --allow-unsigned-rpm "$pkg" ;;
    pacman)
        pacman -U --noconfirm "$pkg" || die "pacman refused the package.
Arch's default SigLevel rejects unsigned local packages, and LabDesk does not
sign them. To install anyway, download the package and install it with a pacman
config that sets 'SigLevel = Never', accepting that nothing verifies it:
  $url"
        ;;
esac

command -v rustdesk >/dev/null 2>&1 || die "install finished but the rustdesk binary is not on PATH."

# Apply every setting that was supplied and report the ones that did not take,
# rather than dying part-way and leaving a half-pointed client with no record
# of which settings landed.
applied=""
failed=""
# `rustdesk --option` exits 0 whatever happens: in the shipped source every
# branch, including "Installation and administrative privileges required!",
# returns None. Reading the value back is the only way to know whether the write
# landed. This also catches the case below, where there is no session to write
# to. The value is printed on its own line; take the last non-empty one.
set_option() {
    [ -n "${2:-}" ] || return 0
    rustdesk --option "$1" "$2" >/dev/null 2>&1 || true
    actual=$(rustdesk --option "$1" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n 1 || true)
    if [ "$actual" = "$2" ]; then
        applied="$applied $1"
    else
        failed="$failed $1"
    fi
}

if [ -n "${LABDESK_HOST:-}${LABDESK_RELAY:-}${LABDESK_API:-}${LABDESK_KEY:-}" ]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet rustdesk || systemctl start rustdesk || true
    fi
    set_option custom-rendezvous-server "${LABDESK_HOST:-}"
    set_option relay-server "${LABDESK_RELAY:-}"
    set_option api-server "${LABDESK_API:-}"
    set_option key "${LABDESK_KEY:-}"
    if [ -n "$applied" ]; then info "applied:$applied"; fi
    if [ -n "$failed" ]; then
        warn "could not apply:$failed
The client is installed but is not pointed at your server. Settings are written
through the LabDesk instance running in a logged-in user's session, not through
the root service, so on a machine nobody has logged into yet there is nothing to
write to. Log in on this machine once, then set them:
  sudo rustdesk --option custom-rendezvous-server <host>
Or set them in the GUI under Settings > Network."
    fi
else
    info "no server settings given, so none were changed"
fi

# Wayland has had experimental support since 1.2.0, so a Wayland desktop works.
# What does not work is reaching the *login screen* after a reboot or logout,
# which still needs X11. Say so rather than let someone discover it the first
# time a machine reboots with nobody sitting at it.
session="${XDG_SESSION_TYPE:-}"
if [ -z "$session" ] && [ -n "$(find /run/user -maxdepth 2 -name 'wayland-*' -print -quit 2>/dev/null)" ]; then
    session=wayland
fi
if [ "$session" = "wayland" ]; then
    warn "this machine is running a Wayland session.
Wayland support is experimental, and connecting to the login screen after a
reboot or logout is not supported on it. If you need to reach this machine
when nobody is logged in, switch the login screen to X11 and reboot:
  sudo sed -i 's/^#*WaylandEnable=.*/WaylandEnable=false/' /etc/gdm/custom.conf
  (Debian and Ubuntu use /etc/gdm3/custom.conf)
The path above is for GDM; on KDE or another display manager the setting lives
elsewhere."
    if [ "$manager" = "apt" ] && [ "$arch" = "x86_64" ]; then
        warn "LabDesk also publishes a separate 'rustdesk-unattended-wayland' deb that
captures through DRM/KMS with no X11 switch. It is a distinct package on purpose
because it bypasses the desktop's consent prompt and injects input as root, so
install it deliberately rather than as part of a routine setup:
  https://github.com/$REPO/releases/latest"
    fi
fi

info "done. Launch LabDesk from your applications menu or run 'rustdesk'."
