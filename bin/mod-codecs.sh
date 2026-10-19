#!/usr/bin/env bash
# Doctor: multimedia codecs (videos/music that won't play on fresh installs).
# Detect: ffmpeg present with mp3/aac/h264 decoders. Fix: per-distro codec
# packages (all open-source code; patent-encumbered ones come from the
# community repos RPM distros use for exactly this: Packman, RPM Fusion).
# Usage: mod-codecs.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# standalone-safe: dispatcher exports PM, direct runs detect it
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"

codecs_ok() {
  have ffmpeg || return 1
  # decoders, not encoders: libmp3lame is encoder-only and never shows in
  # -decoders - asking for it there flagged healthy systems as broken.
  local dec
  dec=$(ffmpeg -hide_banner -decoders 2>/dev/null) || return 1
  echo "$dec" | grep -qE " mp3(float)?( |$)" \
    && echo "$dec" | grep -qE " aac( |$)" \
    && echo "$dec" | grep -qE " h264( |$)"
}

main_fix() {
  # base codec packages per distro; each reported honestly by install_pkgs
  ensure_sudo || exit 1
case "$PM" in
  zypper)
    if ! zypper lr 2>/dev/null | grep -qi packman; then
      echo "adding packman-essentials repo (community codec repo)..."
      if grep -qi tumbleweed /etc/os-release 2>/dev/null; then
        sudo zypper addrepo -f https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/Essentials/ packman-essentials || exit 1
      else
        ver=$(grep -oP '^VERSION_ID="\K[^"]+' /etc/os-release 2>/dev/null || echo "15.6")
        sudo zypper addrepo -f "https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Leap_$ver/Essentials/" packman-essentials || exit 1
      fi
    fi
    install_pkgs zypper ffmpeg vlc-codecs gstreamer-plugins-libav gstreamer-plugins-bad-codecs gstreamer-plugins-ugly-codecs || true
    ;;
  dnf)
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
      echo "adding RPM Fusion repos (community codec repo)..."
      fed=$(rpm -E %fedora 2>/dev/null || echo 41)
      sudo dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$fed.noarch.rpm" \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fed.noarch.rpm" || exit 1
    fi
    sudo dnf group install -y multimedia sound-and-video 2>&1 | tail -n 2 || true
    ;;
  pacman)
    install_pkgs pacman gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav ffmpeg || true
    ;;
  apt)
    install_pkgs apt libavcodec-extra gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly || true
    echo "note: ubuntu-restricted-extras (needs MS-font EULA) is manual:"
    echo "  sudo apt install ubuntu-restricted-extras   # Debian/Ubuntu"
    echo "  sudo apt install mint-meta-codecs           # Linux Mint"
    ;;
  *) echo "unsupported distro for codecs"; exit 1 ;;
esac

if codecs_ok; then
  echo "ok - codecs play now"
else
  echo "FAILED - still no decoders (see lines above)"
  exit 1
fi
} # main_fix

if codecs_ok; then
  echo "ok - codecs play (mp3/aac/h264 decode in ffmpeg)"
else
  echo "NEEDS FIX - videos/music may not play (ffmpeg or decoders missing)"
  [ "$MODE" = "fix" ] || exit 2
  main_fix
fi

# --- bluetooth audio codecs (Maid BT quality lock needs these offered) ---
# Detect from the live card, never guess: LDAC/AAC profiles present?
# Missing libs are best-known names per distro, each reported honestly.
# New libs need a pipewire restart to re-enumerate (printed, not assumed).
if have pactl && pactl list short cards 2>/dev/null | grep -qi bluez; then
  cardcodecs=$(pactl list cards 2>/dev/null)
  bt_missing=""
  echo "$cardcodecs" | grep -q "codec LDAC" || bt_missing="$bt_missing LDAC"
  echo "$cardcodecs" | grep -q "codec AAC" || bt_missing="$bt_missing AAC"
  if [ -z "$bt_missing" ]; then
    echo "ok - bluetooth offers LDAC + AAC (Maid BT quality lock has what it needs)"
  else
    echo "NEEDS FIX - bluetooth card lacks:$bt_missing (Maid BT falls back to SBC)"
    [ "$MODE" = "fix" ] || exit 2
    case "$PM" in
      zypper) install_pkgs zypper libldac2 libfdk-aac2 libfreeaptx0 || true ;;
      dnf)
        install_pkgs dnf pipewire-codec-aptx || true
        echo "note: LDAC ships in Fedora pipewire already; AAC has no clean Fedora path (fdk banned)"
        ;;
      pacman)
        install_pkgs pacman libldac libfreeaptx || true
        echo "note: AAC needs libfdk-aac (check extra) if still missing"
        ;;
      apt)
        install_pkgs apt libldacbt-enc2 libfreeaptx0 libfdk-aac2 || true
        echo "note: libfdk-aac2 needs non-free enabled"
        ;;
    esac
    echo "restart audio to re-enumerate codecs:"
    echo "  systemctl --user restart pipewire pipewire-pulse wireplumber"
    echo "rerun maid-helper --check afterwards to confirm LDAC/AAC appear"
  fi
else
  echo "skip - no bluetooth audio card right now (buds away?)"
fi
