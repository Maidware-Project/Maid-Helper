# AGENTS.md — Maid Helper (for AI assistants; humans see README.md)

One maintainer plus friends helping out — keep every change small,
reviewable, and justified. No drive-by refactors, no new dependencies
without asking.

Honesty is non-negotiable: say what you actually did versus what you
were asked to do. Never claim a test ran, a build passed, or hardware
was verified unless it truly happened in this session. Report failures
and shortcuts plainly, mark uncertainty as uncertainty, and never hide
a skipped step behind vague wording.

People over AI, always: this project is human-built and human-reviewed.
AI assists, humans decide. Write code, messages, and docs a person can
follow with no assistant involved — clear names, plain language, no
cleverness. The goal is users who understand their system, not users
dependent on one.

First-aid kit for new (and older) Linux users: codecs, GPU, printer,
fonts. Detect, report, offer the fix. Android/Linux desktop only,
like the rest of the suite.

## Layout

- `bin/maid-helper` dispatcher (`--check` reports, `--fix` applies,
  `--only a,b` selects modules)
- `bin/mod-*.sh` one doctor module each (codecs, gpu, print, fonts,
  suite, gamepad, flatpak, firmware), distro backends auto-detected
  from `/etc/os-release`
- `desktop/` launcher, `install.sh` multi-distro installer,
  `tests/` suite + fixtures + stubs

## Rules

- Fully open source, FLOSS compliant: MIT code, no proprietary blobs
  shipped, downloaded, or installed — ever. The NVIDIA module works
  the open stack (Nouveau) only and won't print vendor-driver
  commands either. Microsoft fonts install only with explicit user
  consent — interactive prompt on a tty, or MSFONTS=1. Non-interactive
  runs without consent print instructions and report NEEDS ATTENTION
  instead.
- No personal data in repo. Installer copies, never symlinks, backs up.
- `--check` reports, changes nothing. `--fix` is the only path that
  installs anything or restarts anything. Manual steps (reboot, MOK
  password, test page) are printed, never performed silently.
- Package names differ per distro and go stale — every install reports
  per-package success/fail plainly, never aborts the whole run on one
  missing package, never claims success it didn't verify.
- Never hold packages; never auto-enroll Secure Boot keys.

## Verify

- `bash tests/run.sh` — stub farm fakes package managers and
  detectors, safe anywhere
- `bash install.sh --check` — dry run
- Uninstaller contract: `--uninstall` keeps settings (asks), `--purge`
  removes everything. Test both with a fake HOME, never the live one.

Before finishing: pass docs/REVIEW.md.
