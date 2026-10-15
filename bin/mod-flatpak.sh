#!/usr/bin/env bash
# Doctor: flathub remote (fresh installs can have flatpak with nowhere
# to install from). Detect: flathub listed. Fix: user-level remote-add
# (no sudo, no system change). Verify: listed afterwards.
# Usage: mod-flatpak.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"

MODE="${1:-check}"

flathub_ok() {
  have flatpak || return 1
  flatpak remotes 2>/dev/null | grep -qi flathub || return 1
}

if flathub_ok; then
  echo "ok - flathub remote present"
  exit 0
fi
have flatpak || echo "NEEDS FIX - flatpak itself missing"
echo "NEEDS FIX - flathub remote missing (flatpak has nowhere to install from)"
[ "$MODE" = "fix" ] || exit 2

if ! have flatpak; then
  ensure_sudo || exit 1
  case "$PM" in
    zypper) install_pkgs zypper flatpak || exit 1 ;;
    dnf) install_pkgs dnf flatpak || exit 1 ;;
    pacman) install_pkgs pacman flatpak || exit 1 ;;
    apt) install_pkgs apt flatpak || exit 1 ;;
    *) echo "unsupported distro for flatpak"; exit 1 ;;
  esac
fi
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>&1 | tail -n 1 || true
if flathub_ok; then
  echo "ok - flathub remote added"
else
  echo "FAILED - flathub still not listed"
  exit 1
fi
