#!/usr/bin/env bash
# Doctor: Maid suite wholeness (BT, AU, Maidshare, Watcher installed,
# configured, running?). Never installs or fixes anything itself — prints
# the exact command that does, so every sibling keeps its own autonomy.
# check and fix behave the same (fix just re-checks). rc: 0 whole,
# 2 something missing (with the command to fix it).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# standalone-safe: dispatcher exports PM, direct runs detect it
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"
MISS=0
miss() { echo "NEEDS FIX - $1"; echo "  run: $2"; MISS=1; }

# --- Maid BT: switcher, conf MAC, watcher service ---
if [ -x "$HOME/.local/bin/bluetooth-toggle.sh" ]; then
  if grep -q '^BUDS_MAC="\(AA:BB:CC:DD:EE:FF\)\?"' "$HOME/.config/bluetooth-buds.conf" 2>/dev/null; then
    miss "Maid BT installed but no earbuds MAC configured" \
      "bash ~/Documents/GitHub/Maid\\ BT/install.sh  # prompts for MAC"
  elif systemctl --user is-active buds-fallback.service >/dev/null 2>&1; then
    echo "ok - Maid BT installed, configured, watcher running"
  else
    miss "Maid BT watcher not running" \
      "systemctl --user enable --now buds-fallback.service"
  fi
else
  miss "Maid BT not installed" "cd ~/Documents/GitHub/Maid\\ BT && bash install.sh"
fi

# --- Maid AU: updater present ---
if [ -x "$HOME/.local/bin/update-all.sh" ]; then
  echo "ok - Maid AU installed"
else
  miss "Maid AU not installed" "cd ~/Documents/GitHub/Maid\\ AU && bash install.sh"
fi

# --- Maidshare: dispatcher + at least one backend usable ---
if [ -x "$HOME/.local/bin/maidshare" ]; then
  backends=""
  have kdeconnect-cli && backends="$backends kdeconnect"
  have adb && backends="$backends adb"
  have python3 && have openssl && backends="$backends http"
  if [ -n "$backends" ]; then
    echo "ok - Maidshare installed (backends:$backends )"
  else
    miss "Maidshare installed but no backend usable (need kdeconnect, adb, or python3+openssl)" \
      "sudo zypper install kdeconnect-kde # or android-tools, python3, openssl"
  fi
else
  miss "Maidshare not installed" "cd ~/Documents/GitHub/Maidshare && bash install.sh"
fi

# --- Maid Watcher: daemon + real MACs configured ---
if [ -x "$HOME/.local/bin/maid-watcher" ]; then
  if grep -q "AA:BB:CC:DD:EE:FF" "$HOME/.config/maid-watcher/config.json" 2>/dev/null; then
    miss "Maid Watcher installed but still placeholder MACs" \
      "edit ~/.config/maid-watcher/config.json (maid-watcher scan lists devices)"
  else
    echo "ok - Maid Watcher installed and configured"
  fi
else
  echo "skip - Maid Watcher not installed (optional; ships inside Maid BT)"
fi

[ "$MISS" = "0" ] && exit 0
[ "$MODE" = "fix" ] && echo "(fix mode re-checked; run the commands above)" || true
exit 2
