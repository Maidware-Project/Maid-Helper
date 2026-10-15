#!/usr/bin/env bash
# Doctor: GPUs on the open stack (Nouveau for NVIDIA, amdgpu for AMD).
# Maid Helper does not install proprietary drivers, ever — no consent
# flag, no vendor-driver commands printed either. ROCm/compute is out
# of scope (gaming/desktop rendering only).
# NVIDIA: Nouveau in use, nothing blacklisted, no nomodeset.
# AMD: amdgpu in use, firmware package present, Vulkan ICD present.
# GCN 1.0/1.1 cards stuck on radeon get printed kernel flags (bootloader
# edits stay manual, always). Fixes back up what they touch.
# Test seams: MAID_MODPROBE_D and MAID_CMDLINE override the paths read.
# Usage: mod-gpu.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"

MODE="${1:-check}"
MP_D="${MAID_MODPROBE_D:-/etc/modprobe.d}"
CMDLINE="${MAID_CMDLINE:-/proc/cmdline}"
VK_DIR="${MAID_VULKAN_DIR:-/usr/share/vulkan/icd.d}"
NEED=0
need() { echo "NEEDS FIX - $1"; NEED=1; }

have_nvidia=0
have_amd=0
if have lspci; then
  lspci -nn 2>/dev/null | grep -qi nvidia && have_nvidia=1
  lspci -nn 2>/dev/null | grep -Ei "VGA|3D|Display" | grep -qiE "amd|ati|radeon|1002" && have_amd=1
elif ! have nvidia-smi; then
  echo "NEEDS FIX - can't tell (pciutils missing, so GPUs are invisible)"
  [ "$MODE" = "fix" ] || exit 2
  ensure_sudo || exit 1
  case "$PM" in
    zypper) install_pkgs zypper pciutils || exit 1 ;;
    dnf) install_pkgs dnf pciutils || exit 1 ;;
    pacman) install_pkgs pacman pciutils || exit 1 ;;
    apt) install_pkgs apt pciutils || exit 1 ;;
    *) echo "unsupported distro"; exit 1 ;;
  esac
  exit 2  # rerun to detect with lspci present
fi

if [ "$have_nvidia" = "0" ] && [ "$have_amd" = "0" ]; then
  if have nvidia-smi && nvidia-smi >/dev/null 2>&1; then :; else
    echo "ok - no NVIDIA/AMD GPU found (nothing to do)"
    exit 0
  fi
fi

driver_of() {
  # $1 = grep pattern for the device line; echo "Kernel driver in use" value
  lspci -k 2>/dev/null | grep -A2 -i "$1" | grep -oP "Kernel driver in use: \K.*" | head -n 1
}

# ---- NVIDIA on Nouveau ----
if [ "$have_nvidia" = "1" ]; then
  if lsmod 2>/dev/null | grep -q "^nvidia "; then
    echo "note - proprietary NVIDIA stack is loaded; Helper leaves it alone"
    echo "  (want Nouveau instead? remove the vendor driver per your distro's docs, then rerun)"
  else
    driver=$(driver_of nvidia)
    bl_files=$(grep -rlE "blacklist.*nouveau|nouveau.*blacklist|blacklist.*nvidia|options nouveau.*modeset=0" "$MP_D" 2>/dev/null || true)
    cmdline=$(cat "$CMDLINE" 2>/dev/null || true)
    noms=0
    echo "$cmdline" | grep -qw "nomodeset" && noms=1
    echo "$cmdline" | grep -q "modprobe.blacklist=nouveau" && noms=1
    if [ "$driver" = "nouveau" ] && [ -z "$bl_files" ] && [ "$noms" = "0" ]; then
      echo "ok - Nouveau driving the NVIDIA GPU, nothing blacklisted"
    else
      need "NVIDIA present but Nouveau not driving it (driver: ${driver:-none})"
      [ -n "$bl_files" ] && echo "$bl_files" | sed 's/^/  blacklisted in: /'
      [ "$noms" = "1" ] && echo "  kernel cmdline blocks modesetting (nomodeset/blacklist)"
      if [ "$MODE" = "fix" ]; then
        ensure_sudo || exit 1
        if [ -n "$bl_files" ]; then
          echo "$bl_files" | while read -r f; do
            [ -n "$f" ] || continue
            sudo cp -a "$f" "$f.maid-bak" 2>/dev/null || true
            sudo sed -i -E 's/^(\s*)(blacklist +(nouveau|nvidia).*|options +nouveau.*modeset=0.*)/\1# maid-helper disabled: \2/' "$f" \
              && echo "  unblacklisted in $f (backup: $f.maid-bak)"
          done
        fi
        case "$PM" in
          zypper|dnf) sudo dracut -f 2>&1 | tail -n 1 || true ;;
          pacman) sudo mkinitcpio -P 2>&1 | tail -n 2 || true ;;
          apt) sudo update-initramfs -u 2>&1 | tail -n 1 || true ;;
        esac
        if [ "$noms" = "1" ]; then
          echo "REMAINING MANUAL STEP - remove nomodeset from your bootloader:"
          echo "  openSUSE/Fedora: sudo grubby --remove-args=nomodeset --update-kernel=ALL"
          echo "  Arch: edit /boot/loader/entries/*.conf (or grub config), then reboot"
          echo "  Debian/Ubuntu: edit /etc/default/grub, sudo update-grub, then reboot"
        fi
        echo "reboot, then rerun --check"
      fi
    fi
  fi
fi

# ---- AMD on amdgpu ----
if [ "$have_amd" = "1" ]; then
  drv=$(lspci -k 2>/dev/null | awk 'tolower($0) ~ /vga|3d|display/ {amd=tolower($0) ~ /amd|ati|radeon|1002/} amd && /Kernel driver in use:/ {print $NF; amd=0}' | head -n 1)
  if [ "$drv" = "amdgpu" ]; then
    fw_ok=1; vk_ok=1
    case "$PM" in
      zypper) pkg_present kernel-firmware-amdgpu || fw_ok=0 ;;
      dnf) pkg_present linux-firmware || fw_ok=0 ;;
      pacman) pkg_present linux-firmware || fw_ok=0 ;;
      apt) pkg_present firmware-amd-graphics || fw_ok=0 ;;
    esac
    ls "$VK_DIR"/*radeon* "$VK_DIR"/*amd* >/dev/null 2>&1 || vk_ok=0
    if [ "$fw_ok" = "1" ] && [ "$vk_ok" = "1" ]; then
      echo "ok - amdgpu driving AMD GPU, firmware + Vulkan present"
    else
      need "amdgpu loaded but incomplete (firmware: $fw_ok, vulkan: $vk_ok)"
      if [ "$MODE" = "fix" ]; then
        ensure_sudo || exit 1
        case "$PM" in
          zypper) install_pkgs zypper kernel-firmware-amdgpu libvulkan_radeon || true ;;
          dnf) install_pkgs dnf linux-firmware mesa-vulkan-drivers || true ;;
          pacman) install_pkgs pacman linux-firmware vulkan-radeon || true ;;
          apt) install_pkgs apt firmware-amd-graphics mesa-vulkan-drivers || true ;;
        esac
        echo "reboot if firmware was just installed, then rerun --check"
      fi
    fi
  elif [ "$drv" = "radeon" ]; then
    need "AMD card on legacy radeon driver (no Vulkan, weaker power management)"
    echo "  GCN 1.0/1.1 cards can switch to amdgpu with kernel flags (bootloader edit, manual):"
    echo "  amdgpu.si_support=1 amdgpu.cik_support=1 radeon.si_support=0 radeon.cik_support=0"
    echo "  older cards stay on radeon (fine for desktop, no Vulkan)"
  else
    need "AMD GPU present, no driver bound (driver: ${drv:-none})"
  fi
fi

# rc 2 whenever anything needs attention (including "reboot to finish").
[ "$NEED" = "0" ] && exit 0
exit 2
