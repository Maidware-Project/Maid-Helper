# Maid Helper — first-aid kit for linux

new (and older) linux users hit the same four walls: videos won't
play, the NVIDIA GPU sits idle, the printer won't print, fonts look
wrong. this checks all four and fixes what it safely can.

```
bin/maid-helper          dispatcher
bin/mod-codecs.sh        videos/music codecs (ffmpeg, gstreamer, BT audio)
bin/mod-gpu.sh           NVIDIA driver (proprietary only with consent)
bin/mod-print.sh         CUPS + driverless printers
bin/mod-fonts.sh         emoji + CJK + MS fonts (MS only with consent)
bin/mod-suite.sh         is the rest of the Maid suite whole?
bin/lib.sh               shared bits (never run directly)
install.sh               multi-distro installer
```

## usage

```sh
maid-helper --check           # report only, changes nothing (default)
maid-helper --fix             # detect + apply fixes (sudo inside)
maid-helper --only codecs     # one module: codecs|gpu|print|fonts|suite
```

exit codes: `0` healthy/fixed, `2` needs attention, anything else failed.

## fully open source, floss compliant

MIT, like the rest of the suite. non-free software (NVIDIA drivers,
Microsoft fonts) installs **only** with your explicit yes — a prompt
on interactive terminals, or `NVIDIA_PROPRIETARY=1` / `MSFONTS=1`.
without consent it prints the manual path and reports NEEDS ATTENTION
instead. patent-encumbered codecs come from the community repos your
distro already uses for this (Packman, RPM Fusion) — said plainly in
the output, never hidden.

## what it needs per distro

| need | arch | debian/ubuntu | fedora | opensuse |
|---|---|---|---|---|
| GPU detect | pciutils | pciutils | pciutils | pciutils |
| everything else | stock tools | stock tools | stock tools | stock tools |

no services here — runs on demand, so init doesn't matter.

## safety

- `--check` never changes anything. `--fix` is the only path that
  installs or restarts.
- every package install reports per-package success/fail — one stale
  package name never fails the whole run silently.
- reboot, Secure Boot key enrollment, and test pages stay manual,
  printed as exact commands, never performed.
- never holds packages; never auto-enrolls Secure Boot keys.
- NVIDIA branch defaults to G06 (Turing and newer); override per run:
  `NVIDIA_BRANCH=G05 maid-helper --fix`.

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
