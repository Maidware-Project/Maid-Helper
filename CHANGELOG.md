# changelog

## more doctors: gamepad, flatpak, firmware, AMD

- new modules: gamepads (USB + bluetooth detect, Steam Input noted
  first, delegates to Maid AU's stack on openSUSE), flathub remote,
  fwupd presence — same check/fix contract as the rest.
- gpu covers AMD now (amdgpu + firmware + Vulkan verified, legacy
  radeon gets printed kernel flags); NVIDIA stays Nouveau-only,
  nothing proprietary anywhere.
- distros: derivatives ride their family (manjaro, mint, pop, rocky);
  unknown distros get manual commands, tested via fixtures.

## first release

- five doctor modules (codecs, gpu, print, fonts, suite) behind one
  dispatcher: `--check` reports, `--fix` applies, `--only` selects.
  exit codes 0 healthy / 2 needs attention / else failed.
- codecs: ffmpeg decoder check + per-distro codec packs (Packman,
  RPM Fusion, Arch, apt) plus a live-card bluetooth ladder check
  (LDAC/AAC for Maid BT), with pipewire-restart guidance.
- gpu: NVIDIA detect, proprietary driver only with explicit consent,
  reboot + Secure Boot MOK stay manual and printed.
- print: CUPS + avahi enablement, HP note, test page printed as a
  command, never auto-printed.
- fonts: Noto emoji/CJK by default; MS fonts only with consent.
- suite: sibling wholeness check that never installs, only points.
- stub-farm test suite (9 checks), fake-HOME installer contract.
