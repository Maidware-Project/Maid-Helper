#!/usr/bin/env bash
# Doctor: gamepads (Xbox/PlayStation/Switch/8BitDo pads with no driver).
# Detect: USB VIDs + paired bluetooth names. If nothing found, healthy
# (nothing to do). Steam Input already covers most pads with zero
# drivers — said plainly before any package is suggested.
# openSUSE defers to Maid AU's setup-controllers.sh when present (its
# stack, its rules); elsewhere per-distro best effort. Kernel-module
# installs need a replug/reboot to verify — printed, never assumed.
# Usage: mod-gamepad.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# standalone-safe: dispatcher exports PM, direct runs detect it
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"

pads=""
if have lsusb; then
  # VIDs + strong keywords only: bare "controller" matches motherboard
  # LED/lighting gear (e.g. ASUS AURA LED Controller), not gamepads.
  pads=$(lsusb 2>/dev/null | grep -iE "045e|054c|057e|28de|2dc8|xbox|playstation|dualshock|dualsense|nintendo|8bitdo|gamepad" || true)
fi
if [ -z "$pads" ] && have bluetoothctl; then
  pads=$(bluetoothctl devices 2>/dev/null | grep -iE "xbox|playstation|dualshock|dualsense|nintendo|switch|8bitdo|gamepad|controller" || true)
fi
if [ -z "$pads" ]; then
  echo "ok - no gamepads detected (nothing to do)"
  exit 0
fi
echo "found gamepad(s):"
echo "$pads" | head -n 4 | sed 's/^/  /'
echo "note: Steam Input already drives most of these with no drivers (Steam > Settings > Controller)"
echo "NEEDS FIX - gamepad drivers not ensured"
[ "$MODE" = "fix" ] || exit 2

# openSUSE: Maid AU owns this stack — defer, don't duplicate.
if [ "$PM" = "zypper" ] && [ -x "$HOME/.local/bin/setup-controllers.sh" ]; then
  echo "delegating to Maid AU's controller stack..."
  if [ -t 0 ]; then
    "$HOME/.local/bin/setup-controllers.sh" || exit 1
  else
    "$HOME/.local/bin/setup-controllers.sh" --update || exit 1
  fi
  echo "ok - controller stack run (replug pad / reboot for kernel modules, then test in Steam)"
  exit 0
fi

ensure_sudo || exit 1
case "$PM" in
  zypper)
    install_pkgs zypper xone-kmp-default xpadneo-kmp-default joycond inputplumber hid-tmff2-kmp-default || true
    ;;
  pacman)
    if consent "build AUR packages for gamepads (runs other people's build code)?" UPDATE_AUR; then
      helper=""
      have yay && helper=yay
      [ -z "$helper" ] && have paru && helper=paru
      if [ -z "$helper" ]; then
        echo "  no AUR helper (yay/paru) — install one, then: yay -S xone-dkms xpadneo-dkms"
        exit 2
      fi
      $helper -S --needed --noconfirm xone-dkms xpadneo-dkms 2>&1 | tail -n 2 || true
      install_pkgs pacman joycond inputplumber || true
    else
      echo "  skipped AUR builds (needs UPDATE_AUR=1 or a yes above)"
      exit 2
    fi
    ;;
  dnf|apt)
    echo "  no packaged drivers here — Steam Input covers these pads; vendor DKMS/COPR builds vary by kernel"
    echo "  Fedora: check community COPR for xone/xpadneo matching your kernel"
    echo "  Debian/Ubuntu: xpadneo-dkms exists in some releases — try: sudo apt install xpadneo-dkms"
    exit 2
    ;;
  *) echo "unsupported distro for gamepads"; exit 1 ;;
esac
echo "ok - gamepad packages attempted (replug pad / reboot for kernel modules, then test in Steam)"
