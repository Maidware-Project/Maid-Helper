# changelog

## kdeconnect: one version-independent early-login fix

- new `kdeconnect` doctor: detects the KDE Connect D-Bus early-login
  crash and installs a user wrapper plus D-Bus/autostart overrides. no
  root, no package rebuild, survives KDE Connect updates; takes effect
  at the next login.
- the upstream-style source patch is shipped under
  `patches/kdeconnect-26.08.2/` and attached to GitHub releases for
  distro/upstream use. the old RPM-style duplicate is gone.
- the sibling installers no longer carry their own copies of the patch:
  one suite fix, one place. `maid-helper --only kdeconnect --fix` is the
  documented path (Maid BT, Maidshare, Maid AU, Maid Runner, Watcher
  changelogs point here).

## fixes: an honest codecs check, a window you can read

- codecs: the check asked ffmpeg's *decoder* list for libmp3lame - an
  encoder only - so healthy systems were told "NEEDS FIX - videos/music
  may not play". it now checks the decoders that matter (mp3/aac/h264),
  and the stub farm fakes real ffmpeg output so the old bug can't hide
  behind the test again.
- launcher: the terminal window no longer vanishes the moment the report
  ends - it waits for enter, and when the check found trouble it offers
  to apply the safe fixes right there (sudo asks inside). a desktop
  default terminal that is no longer installed now falls back instead of
  failing silently.
- dispatcher: the run log the readme and uninstaller promise
  (`~/.local/share/maid-helper.log`) is finally written - run header,
  every module's output, result line.
- print: "no system default destination" is said in words instead of
  leaking raw lpstat output; the Maidshare backend list loses its stray
  trailing space.

## more doctors: gamepad, flatpak, firmware, AMD

- new modules: gamepads (USB + bluetooth detect, Steam Input noted
  first, delegates to Maid AU's stack on openSUSE), flathub remote,
  fwupd presence - same check/fix contract as the rest.
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
