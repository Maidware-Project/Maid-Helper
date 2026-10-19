# Review checklist - pass all five before any change ships

1. **Plain words.** Could a non-technical friend follow the README
   diff with no help? No jargon without an explanation next to it.
2. **Off by default.** Nothing installs, restarts, or reboots unless
   asked (`--fix`). Manual steps stay manual (reboot, MOK, test page).
3. **Proven, not claimed.** `bash tests/run.sh` green on stub farm.
   Hardware paths (real GPU, real printer) verified live when touched.
4. **Docs match code.** README, CHANGELOG updated with the behavior.
   No personal data anywhere.
5. **Uninstall story intact.** `--uninstall` asks about settings/logs,
   `--purge` removes everything. Tested with a fake HOME, never live.
