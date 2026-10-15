#!/usr/bin/env bash
# Doctor: fonts (missing emoji/CJK, ugly fallbacks, no Office-compatible fonts).
# Default installs open fonts only (Noto families). Microsoft core fonts are
# non-free: installed only with explicit consent (tty prompt, or MSFONTS=1),
# never silently, never assumed. fc-cache + recount verifies.
# Usage: mod-fonts.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# standalone-safe: dispatcher exports PM, direct runs detect it
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"

fc_count() { fc-list 2>/dev/null | grep -ciE "$1"; }

emoji=$(fc_count "noto.*emoji|emoji.*noto|color emoji")
cjk=$(fc_count "noto.*cjk|cjk.*noto")
[ "$emoji" -gt 0 ] && [ "$cjk" -gt 0 ] && {
  echo "ok - emoji + CJK covered (noto present)"
  exit 0
}
echo "NEEDS FIX - emoji fonts: $emoji families, CJK fonts: $cjk families"
[ "$MODE" = "fix" ] || exit 2

ensure_sudo || exit 1
case "$PM" in
  zypper)
    install_pkgs zypper google-noto-coloremoji-fonts google-noto-sans-cjk-fonts || true
    ;;
  dnf)
    install_pkgs dnf google-noto-emoji-color-fonts google-noto-sans-cjk-fonts || true
    ;;
  pacman)
    install_pkgs pacman noto-fonts noto-fonts-cjk noto-fonts-emoji || true
    echo "note: MS fonts (ttf-ms-fonts) live in the AUR — install by hand if wanted"
    ;;
  apt)
    install_pkgs apt fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji || true
    echo "note: MS fonts need a EULA click-through: sudo apt install ttf-mscorefonts-installer"
    ;;
  *) echo "unsupported distro for fonts"; exit 1 ;;
esac

if consent "also install Microsoft core fonts (non-free EULA, Arial/Times)?" MSFONTS; then
  case "$PM" in
    zypper) install_pkgs zypper fetchmsttfonts || true ;;
    dnf) echo "  Fedora: no repo package — fetch MS fonts by hand if wanted" ;;
    pacman) echo "  Arch: ttf-ms-fonts lives in the AUR — install by hand if wanted" ;;
    apt) echo "  run by hand (EULA screen appears): sudo apt install ttf-mscorefonts-installer" ;;
  esac
else
  echo "  skipped MS fonts (needs MSFONTS=1 or a yes above)"
fi

fc-cache -f >/dev/null 2>&1 || true
emoji=$(fc_count "noto.*emoji|emoji.*noto|color emoji")
cjk=$(fc_count "noto.*cjk|cjk.*noto")
if [ "$emoji" -gt 0 ] && [ "$cjk" -gt 0 ]; then
  echo "ok - emoji + CJK covered now"
else
  echo "FAILED - still missing (emoji=$emoji cjk=$cjk)"
  exit 1
fi
