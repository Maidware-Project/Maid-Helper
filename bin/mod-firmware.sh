#!/usr/bin/env bash
# Doctor: firmware updates available (fwupd missing, so devices never get
# firmware). Detect: fwupdmgr runs. Fix: install the package. Actually
# refreshing/applying firmware stays manual (needs root + a reboot for
# most devices) - printed, never performed.
# Usage: mod-firmware.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# standalone-safe: dispatcher exports PM, direct runs detect it
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"

fw_ok() {
  have fwupdmgr && fwupdmgr --version >/dev/null 2>&1 || return 1
}

if fw_ok; then
  fwupdmgr --version 2>/dev/null | head -n 2 | sed 's/^/  /'
  echo "ok - fwupd present (run: fwupdmgr refresh && fwupdmgr get-updates)"
  exit 0
fi
echo "NEEDS FIX - fwupd missing (no firmware updates possible)"
[ "$MODE" = "fix" ] || exit 2

ensure_sudo || exit 1
case "$PM" in
  zypper) install_pkgs zypper fwupd || exit 1 ;;
  dnf) install_pkgs dnf fwupd || exit 1 ;;
  pacman) install_pkgs pacman fwupd || exit 1 ;;
  apt) install_pkgs apt fwupd || exit 1 ;;
  *) echo "unsupported distro for firmware"; exit 1 ;;
esac
if fw_ok; then
  echo "ok - fwupd installed (next, by hand: fwupdmgr refresh && fwupdmgr get-updates)"
else
  echo "FAILED - fwupd still not working"
  exit 1
fi
