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
like the rest of the suite. Lowercase terse voice in docs (README,
messages, popups).
State live-vs-stub plainly: say what ran on real hardware versus the
stub farm whenever reporting verification.

## What you can't do here

- The interesting parts are hardware: GPU, printer, real fonts, codecs on
  a real machine. The stub farm fakes the detectors and the package
  managers, so it proves the logic, not that the fix works.
- Package names differ per distro and go stale. Nothing here can confirm
  a name is still correct today.
- The `suite` module reports on the other Maid tools; it needs them
  installed to say anything real.

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
- CODE_OF_CONDUCT.md applies to code, comments, and docs:
  technical scope, no politics, stay neutral.
- Commits: short lowercase summaries with a prefix (`fix:`, `feat:`, `docs:`,
  `tests:`, `chore:`), one logical change each. Sign off every commit —
  the trailer is exactly `Signed-off-by: visa`, no email. Bug fixes cite
  `Fixes: #N`.
- `--check` reports, changes nothing. `--fix` is the only path that
  installs anything or restarts anything. Manual steps (reboot, MOK
  password, test page) are printed, never performed silently.
- Package names differ per distro and go stale — every install reports
  per-package success/fail plainly, never aborts the whole run on one
  missing package, never claims success it didn't verify.
- Never hold packages; never auto-enroll Secure Boot keys.

## Principles

Keep it simple ([KISS](https://en.wikipedia.org/wiki/KISS_principle)) and
boring. In practice:

- The smallest change that solves the problem; nothing added "for later"
  (YAGNI).
- One place owns each fact; no repeated logic (DRY).
- Each tool does one thing well and composes (unix philosophy, rule of
  least power).
- Readable beats clever; less is more (worse is better).
- Delete what nothing needs instead of keeping it around.

## Never

- Never push. The maintainer pushes; commits stay local until asked.
- Never ship, download, or install proprietary software or blobs, and
  never print vendor-driver commands.
- Never install Microsoft fonts without explicit consent, and never
  enroll a Secure Boot key on your own.
- Never let `--check` change anything, and never perform a manual step
  (reboot, MOK password, test page) silently.
- Never report hardware you did not verify on real hardware.

## Boundaries (do not touch)

- The `--check` / `--fix` / `--only` contract. `--check` is read-only.
- The module pattern: one `bin/mod-*.sh` per doctor module, distro
  backends auto-detected from `/etc/os-release`.
- The FLOSS rule and the MSFONTS consent gate.
- Package handling: per-package reporting, never aborting the run on one
  missing package, never claiming unverified success.

## Verify

- `bash tests/run.sh` — stub farm fakes package managers and
  detectors, safe anywhere
- `bash install.sh --check` — dry run
- Uninstaller contract: `--uninstall` keeps settings (asks), `--purge`
  removes everything. Test both with a fake HOME, never the live one.

## Making a change

1. `git status -sb` first. A commit or a sync can land while you work,
   and amending something already pushed leaves duplicate commits.
2. Make the smallest diff that solves the stated problem.
3. Run `bash tests/run.sh` and `bash install.sh --check`.
4. On real hardware, run the module you touched — `--check` then
   `--fix`. If you could not, say the change is stub-only.
5. Pass `docs/REVIEW.md`, then commit with a sign-off. Do not push.

## References

- `README.md` — what it fixes, supported distros, module list
- `docs/REVIEW.md` — the checklist to pass before a change ships
- `CONTRIBUTING.md` — how to take part
- `CODE_OF_CONDUCT.md` — scope, and what stays out of the repo
- `CHANGELOG.md` — what changed, release by release
- `SECURITY.md` — how to report a security problem
