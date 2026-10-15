#!/usr/bin/env bash
# Doctor: printing (CUPS off, no driverless discovery, HP missing drivers).
# Detect: CUPS scheduler running + enabled. Fix: install + enable CUPS (and
# avahi for driverless network printers). HP printers get an hplip note.
# Test page is printed as a command for you, never auto-printed (paper!).
# Usage: mod-print.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# standalone-safe: dispatcher exports PM, direct runs detect it
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"

print_ok() {
  have lpstat || return 1
  lpstat -r 2>/dev/null | grep -qi "scheduler is running" || return 1
  systemctl is-enabled cups.service cups.socket cups.path 2>/dev/null | grep -q enabled || return 1
}

if print_ok; then
  lpstat -p -d 2>/dev/null | head -n 3
  echo "ok - CUPS running and enabled"
  exit 0
fi
echo "NEEDS FIX - CUPS not running/enabled"
lpstat -p 2>/dev/null | head -n 5 || true
[ "$MODE" = "fix" ] || exit 2

ensure_sudo || exit 1
case "$PM" in
  zypper) install_pkgs zypper cups cups-filters avahi || true ;;
  dnf) install_pkgs dnf cups cups-filters avahi || true ;;
  pacman) install_pkgs pacman cups cups-filters avahi || true ;;
  apt) install_pkgs apt cups cups-filters avahi-daemon || true ;;
  *) echo "unsupported distro for printing"; exit 1 ;;
esac
sudo systemctl enable --now cups.service 2>&1 | tail -n 1 || true
if have avahi-daemon || have avahi-browse; then
  sudo systemctl enable --now avahi-daemon.service 2>&1 | tail -n 1 || true
fi
echo "note: HP printer? needs hplip too: sudo <pm> install hplip, then run hp-setup"

if print_ok; then
  echo "ok - CUPS running now"
  echo "print a test page yourself when ready: lp -d <printer> /usr/share/cups/data/testprint"
else
  echo "FAILED - CUPS still down (see lines above)"
  exit 1
fi
