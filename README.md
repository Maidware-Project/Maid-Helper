# Maid Helper — first-aid kit for linux

new (and older) linux users hit the same walls: videos won't play,
the GPU sits idle, the printer won't print, fonts look wrong, gamepads
do nothing, flatpak has nowhere to install from, firmware never
updates. this checks the lot and fixes what it safely can.

## quick start

```sh
bash install.sh            # copy + launcher
maid-helper --check        # read-only report, change nothing
maid-helper --fix          # apply the safe fixes (sudo inside)
```

## why not just follow wiki guides?

that's exactly what this automates: the same per-distro package
names and config checks the wikis list, as one read-only `--check`
explaining each finding in plain words — then `--fix` does the safe
parts and prints the manual parts as exact commands. nothing hidden,
nothing irreversible without asking.

live-tested on openSUSE Tumbleweed (AMD); NVIDIA and other-distro
paths ride the stub-farm suite + CI until real hardware confirms
them — the suite tells you which is which.

```
bin/maid-helper          dispatcher
bin/mod-codecs.sh        videos/music codecs (ffmpeg, gstreamer, BT audio)
bin/mod-gpu.sh           NVIDIA (Nouveau) + AMD (amdgpu), open drivers only
bin/mod-print.sh         CUPS + driverless printers
bin/mod-fonts.sh         emoji + CJK + MS fonts (MS only with consent)
bin/mod-gamepad.sh       gamepads (delegates to Maid AU on openSUSE)
bin/mod-flatpak.sh       flathub remote present
bin/mod-firmware.sh      fwupd present for firmware updates
bin/mod-suite.sh         is the rest of the Maid suite whole?
bin/lib.sh               shared bits (never run directly)
install.sh               multi-distro installer
```

## installation

```sh
bash install.sh                # deps (sudo) + copy + launcher
bash install.sh --check        # dry run
bash install.sh --no-packages  # skip installing packages
```

existing files are backed up to `*.bak-<timestamp>` (only when content
actually changed). no network downloads anywhere in this package.

## usage

```sh
maid-helper --check           # report only, changes nothing (default)
maid-helper --fix             # detect + apply fixes (sudo inside)
maid-helper --only codecs     # one module: codecs|gpu|print|fonts|suite|gamepad|flatpak|firmware
```

exit codes: `0` healthy/fixed, `2` needs attention, anything else failed.

## fully open source, floss compliant

MIT, like the rest of the suite. non-free software never installs
here, period — no proprietary GPU path exists in this tool, and the
single exception (Microsoft fonts) installs **only** with your
explicit yes: a prompt on interactive terminals, or `MSFONTS=1`.
without consent it prints the manual path and reports NEEDS ATTENTION
instead. patent-encumbered codecs come from the community repos your
distro already uses for this (Packman, RPM Fusion) — said plainly in
the output, never hidden.

## what you need per distro

| need | arch (+manjaro, endeavour) | debian/ubuntu (+mint, pop, zorin) | fedora (+rhel clones) | opensuse (+leap, slowroll) |
|---|---|---|---|---|
| GPU detect | pciutils | pciutils | pciutils | pciutils |
| everything else | stock tools | stock tools | stock tools | stock tools |

derivatives ride their family's backend automatically (`ID_LIKE`
honored). anything else: `--check` still reports, and every fix path
prints the manual commands instead of failing silently.

no services here — runs on demand, so init doesn't matter. fork it
for whatever setup you run.

## safety

- `--check` never changes anything. `--fix` is the only path that
  installs or restarts.
- every package install reports per-package success/fail — one stale
  package name never fails the whole run silently.
- reboot, Secure Boot key enrollment, bootloader edits, and test
  pages stay manual, printed as exact commands, never performed.
- never holds packages; never auto-enrolls Secure Boot keys.

## ecosystem (maid suite)

- `mod-codecs.sh` also checks bluetooth A2DP codecs off the live card,
  so Maid BT's quality lock has LDAC/AAC to lock onto.
- `mod-suite.sh` checks the siblings are installed, configured, and
  running (BT + watcher service, AU, Maidshare + a usable backend) —
  and prints the exact install command for anything missing. it never
  installs siblings itself.

## uninstall

```sh
bash install.sh --uninstall            # everything out, asks about the log
bash install.sh --uninstall --purge    # everything out including the log
```

## License

MIT — see LICENSE.
