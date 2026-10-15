#!/usr/bin/env bash
# Doctor: NVIDIA GPU (black screen / llvmpipe / Wayland glitches from a
# missing proprietary driver). Nouveau stays untouched (it is the free
# fallback). The proprietary driver installs only with explicit consent
# (tty prompt, or NVIDIA_PROPRIETARY=1) — non-interactive runs without
# consent print instructions and report NEEDS ATTENTION instead.
# Reboot + Secure Boot MOK enrollment stay manual, always (printed).
# Usage: mod-gpu.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"

MODE="${1:-check}"
BRANCH="${NVIDIA_BRANCH:-G06}"

if have nvidia-smi && nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -n 1
  echo "ok - NVIDIA driver loaded"
  exit 0
fi
if have lspci && ! lspci -nn 2>/dev/null | grep -qi nvidia; then
  echo "ok - no NVIDIA GPU found (nothing to do)"
  exit 0
fi
if ! have lspci; then
  echo "NEEDS FIX - can't tell (install pciutils to detect GPUs)"
  [ "$MODE" = "fix" ] || exit 2
  ensure_sudo || exit 1
  case "$PM" in
    zypper) install_pkgs zypper pciutils || true ;;
    dnf) install_pkgs dnf pciutils || true ;;
    pacman) install_pkgs pacman pciutils || true ;;
    apt) install_pkgs apt pciutils || true ;;
  esac
  lspci -nn 2>/dev/null | grep -qi nvidia || { echo "ok - no NVIDIA GPU found (nothing to do)"; exit 0; }
fi
echo "NEEDS FIX - NVIDIA GPU present, no working driver (llvmpipe/software rendering likely)"
[ "$MODE" = "fix" ] || exit 2

if ! consent "install the proprietary NVIDIA driver branch $BRANCH (non-free license)?" NVIDIA_PROPRIETARY; then
  echo "skipped proprietary driver. manual path:"
  echo "  openSUSE: sudo zypper addrepo NVIDIA repo, sudo zypper install nvidia-video-$BRANCH, reboot"
  echo "  Fedora:   RPM Fusion, then: sudo dnf install akmod-nvidia, wait, reboot"
  echo "  Arch:     sudo pacman -S nvidia nvidia-utils (or nvidia-open), reboot"
  echo "  Debian/Ubuntu: sudo apt install nvidia-driver (non-free on) / ubuntu-drivers autoinstall"
  exit 2
fi
ensure_sudo || exit 1
case "$PM" in
  zypper)
    if ! zypper lr 2>/dev/null | grep -qi nvidia; then
      echo "adding NVIDIA repo..."
      if grep -qi tumbleweed /etc/os-release 2>/dev/null; then
        sudo zypper addrepo -f https://download.nvidia.com/opensuse/tumbleweed/ NVIDIA || exit 1
      else
        ver=$(grep -oP '^VERSION_ID="\K[^"]+' /etc/os-release 2>/dev/null || echo "15.6")
        sudo zypper addrepo -f "https://download.nvidia.com/opensuse/leap/$ver/" NVIDIA || exit 1
      fi
    fi
    install_pkgs zypper "nvidia-video-$BRANCH" "nvidia-gl-$BRANCH" || true
    ;;
  dnf)
    if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
      echo "adding RPM Fusion nonfree (for the NVIDIA driver)..."
      fed=$(rpm -E %fedora 2>/dev/null || echo 41)
      sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fed.noarch.rpm" || exit 1
    fi
    install_pkgs dnf akmod-nvidia || true
    echo "akmod builds the kernel module in the background — wait ~5 min, then reboot"
    ;;
  pacman)
    install_pkgs pacman nvidia nvidia-utils || true
    echo "note: Turing+ can use nvidia-open instead; linux-lts needs nvidia-lts"
    ;;
  apt)
    if grep -qi ubuntu /etc/os-release 2>/dev/null; then
      sudo ubuntu-drivers autoinstall 2>&1 | tail -n 2 || true
    else
      install_pkgs apt nvidia-driver || true
      echo "note: Debian needs non-free enabled for nvidia-driver"
    fi
    ;;
  *) echo "unsupported distro for GPU"; exit 1 ;;
esac

echo "REBOOT REQUIRED - the driver loads on next boot, verify then with: nvidia-smi"
if have mokutil && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
  echo "Secure Boot is ON: at reboot, enroll the key when MOK Manager appears"
  echo "(same password you set if asked during install; skip = driver won't load)"
fi
echo "ok - driver installed (reboot to activate)"
