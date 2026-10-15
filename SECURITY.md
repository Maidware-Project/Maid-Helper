# security

Maid Helper flips a few system switches (firmware, gpu, flatpak, gamepad).
how it is kept safe:

- it installs no proprietary drivers. dependencies come from your own
  package manager, over its own signatures; the module fetches nothing
  itself.
- bootloader and kernel-cmdline edits are printed for you to run, never
  applied silently.
- shell uses argv lists; no `eval`, no shell strings.

to report a problem, open an issue on the repository.
