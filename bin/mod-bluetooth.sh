#!/usr/bin/env bash
# Doctor: Maid BT / Bluetooth troubleshooting (Maid BT Helper backend).
# Detect: bluez service, rfkill, adapter power, earbud config, fallback sink,
# PipeWire/Pulse, Maid BT user services, WirePlumber quality config, and
# recent audit-log errors. Fix: only the safe, local parts (service/rfkill/
# adapter/user units). MAC and sink choices stay manual.
# Usage: mod-bluetooth.sh check|fix|report
# rc: 0 healthy/fixed, 2 needs attention, 1 failed.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
: "${PM:=$(detect_pm)}"

MODE="${1:-check}"
CONF="$HOME/.config/bluetooth-buds.conf"
WCONF="$HOME/.config/maid-watcher/config.json"
LOGDIR="$HOME/MaidLogs"
NEED=0
FAILED=0

redact() {
  sed -E \
    -e "s|$HOME|~|g" \
    -e "s|$(hostname 2>/dev/null || echo unknown-host)|maid-pc|g" \
    -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/AA:BB:CC:DD:EE:FF/g'
}

conf_get() {
  local key="$1"
  [ -f "$CONF" ] || return 0
  sed -n -E "s/^[[:space:]]*${key}=[\"']?([^\"']*)[\"']?[[:space:]]*$/\1/p" "$CONF" | tail -n 1
}

unit_installed() {
  systemctl --user list-unit-files "$1" 2>/dev/null | grep -q "^$1"
}

unit_active() {
  systemctl --user is-active --quiet "$1" 2>/dev/null
}

service_active() {
  systemctl is-active --quiet bluetooth 2>/dev/null
}

rfkill_blocked() {
  rfkill list bluetooth 2>/dev/null | grep -qE 'Soft blocked: yes|Hard blocked: yes'
}

adapter_powered() {
  bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'
}

check_stack() {
  echo "== Bluetooth stack =="
  if ! have bluetoothctl; then
    echo "NEEDS FIX - bluetoothctl missing (install bluez)"
    NEED=1
  elif ! have rfkill; then
    echo "NEEDS FIX - rfkill missing (install util-linux/rfkill)"
    NEED=1
  else
    echo "OK - bluez tools present"
  fi

  if service_active; then
    echo "OK - bluetooth.service is running"
  else
    echo "NEEDS FIX - bluetooth.service is not running"
    NEED=1
  fi

  if rfkill_blocked; then
    echo "NEEDS FIX - the Bluetooth radio is blocked by rfkill"
    NEED=1
  else
    echo "OK - Bluetooth radio is not rfkill-blocked"
  fi

  if have bluetoothctl; then
    local show
    show=$(bluetoothctl show 2>/dev/null || true)
    if [ -z "$show" ]; then
      echo "NEEDS FIX - no Bluetooth adapter was found"
      NEED=1
    elif printf '%s\n' "$show" | grep -q 'Powered: yes'; then
      echo "OK - Bluetooth adapter is powered"
    else
      echo "NEEDS FIX - Bluetooth adapter is present but powered off"
      NEED=1
    fi
  fi
}

check_audio() {
  echo "== Audio =="
  if ! have pactl; then
    echo "NEEDS FIX - pactl missing (install pulseaudio-utils/libpulse)"
    NEED=1
    return
  fi
  if ! pactl info >/dev/null 2>&1; then
    echo "NEEDS FIX - PipeWire/PulseAudio is not reachable"
    NEED=1
    return
  fi
  local server
  server=$(pactl info 2>/dev/null | sed -n 's/^Server Name: //p' | head -n 1)
  echo "OK - audio server: ${server:-unknown}"
  local sink
  sink=$(conf_get FALLBACK_SINK)
  if [ -z "$sink" ]; then
    echo "NEEDS FIX - no fallback speaker set in Maid BT"
    NEED=1
  elif pactl list short sinks 2>/dev/null | awk -F '\t' '{print $2}' | grep -Fxq "$sink"; then
    echo "OK - fallback speaker is present"
  else
    echo "NEEDS FIX - fallback speaker '$sink' is not present right now"
    NEED=1
  fi
}

check_config() {
  echo "== Maid BT configuration =="
  if [ ! -f "$CONF" ]; then
    echo "NEEDS FIX - Maid BT config is missing (run the Maid BT installer)"
    NEED=1
    return
  fi
  local mac
  mac=$(conf_get BUDS_MAC)
  if [ -z "$mac" ]; then
    echo "NEEDS FIX - no earbuds MAC configured (run Maid BT setup)"
    NEED=1
  elif printf '%s' "$mac" | grep -Eq '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'; then
    echo "OK - earbuds MAC is configured"
  else
    echo "NEEDS FIX - earbuds MAC is not a valid MAC address (Bash variables are case-sensitive)"
    NEED=1
  fi
  if [ -f "$WCONF" ]; then
    echo "OK - Maid Watcher config is present"
  else
    echo "NOTE - Maid Watcher config is missing (optional watcher features stay off)"
  fi
}

check_scripts() {
  echo "== Maid BT scripts and services =="
  local f missing=0
  for f in bluetooth-toggle.sh buds-fallback.sh; do
    if [ -x "$HOME/.local/bin/$f" ] || [ -x "/usr/bin/$f" ]; then
      echo "OK - $f installed"
    else
      echo "NEEDS FIX - $f is missing (run the Maid BT installer)"
      missing=1
      NEED=1
    fi
  done
  [ "$missing" = "0" ] || true

  local unit
  for unit in buds-fallback.service maid-watcher.service; do
    if unit_installed "$unit"; then
      if unit_active "$unit"; then
        echo "OK - user service $unit is running"
      else
        echo "NEEDS FIX - user service $unit is installed but not running"
        NEED=1
      fi
    else
      echo "NOTE - optional user service $unit is not installed"
    fi
  done
}

check_quality() {
  echo "== Sound quality =="
  if [ "$(conf_get QUALITY_LOCK)" != "1" ]; then
    echo "OK - quality lock is off (LDAC is still offered when available)"
    return
  fi
  if [ -f "$HOME/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf" ]; then
    echo "OK - max-quality WirePlumber config is installed"
  else
    echo "NEEDS FIX - quality lock is on but the WirePlumber config is missing"
    NEED=1
  fi
}

check_logs() {
  echo "== Recent logs =="
  if [ ! -d "$LOGDIR" ]; then
    echo "NOTE - no ~/MaidLogs directory yet (nothing has run)"
    return
  fi
  local hits
  hits=$(grep -IlE 'ERROR|FAILED|Traceback|exception' "$LOGDIR"/*.log 2>/dev/null | head -n 5 || true)
  if [ -n "$hits" ]; then
    echo "WARNING - recent errors found in the Maid logs (see the report for details)"
    printf '%s\n' "$hits" | while IFS= read -r f; do
      echo "  search: $(basename "$f")"
    done
  else
    echo "OK - no recent ERROR/FAILED/Traceback lines in ~/MaidLogs"
  fi
}

do_check() {
  check_stack
  check_audio
  check_config
  check_scripts
  check_quality
  check_logs
  echo
  if [ "$FAILED" != "0" ]; then
    echo "result: FAILED - see the report above"
    exit 1
  fi
  if [ "$NEED" != "0" ]; then
    echo "result: stuff needs fixing - run the safe fixes or open the report"
    exit 2
  fi
  echo "result: all healthy"
  exit 0
}

do_fix() {
  echo "Applying safe Bluetooth fixes..."
  echo
  if ! service_active; then
    echo "- starting bluetooth.service"
    sudo systemctl enable --now bluetooth 2>&1 | tail -n 2 || true
  fi
  if rfkill_blocked; then
    echo "- unblocking the Bluetooth radio"
    sudo rfkill unblock bluetooth 2>&1 || true
  fi
  if have bluetoothctl && ! adapter_powered; then
    echo "- powering the Bluetooth adapter on"
    bluetoothctl power on >/dev/null 2>&1 || true
  fi
  if have pactl && ! pactl info >/dev/null 2>&1; then
    echo "- starting the user audio stack"
    systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true
  fi
  local unit
  for unit in buds-fallback.service maid-watcher.service; do
    if unit_installed "$unit" && ! unit_active "$unit"; then
      echo "- enabling user service $unit"
      systemctl --user enable --now "$unit" 2>&1 | tail -n 2 || true
    fi
  done

  if [ "$(conf_get QUALITY_LOCK)" = "1" ] \
     && [ ! -f "$HOME/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf" ]; then
    local cfg=""
    for cfg in "$HOME/.local/share/maid-bt/52-bt-max-quality.conf" \
               "/usr/share/maid-bt/52-bt-max-quality.conf"; do
      [ -f "$cfg" ] && break
      cfg=""
    done
    if [ -n "$cfg" ]; then
      echo "- installing the max-quality WirePlumber config"
      mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
      cp -a "$cfg" "$HOME/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf"
      systemctl --user restart wireplumber.service 2>/dev/null || true
    else
      echo "!! max-quality config source not found; reinstall Maid BT"
    fi
  fi

  echo
  echo "Manual steps are printed as comments; nothing here changes your MAC or speaker choice."
  echo "Rechecking..."
  echo
  do_check
}

do_report() {
  mkdir -p "$LOGDIR" 2>/dev/null || { echo "cannot create $LOGDIR"; exit 1; }
  local report
  report="$LOGDIR/maid-bt-report-$(date +%Y%m%d-%H%M%S).txt"
  {
    echo "Maid BT Helper support report"
    echo "generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "host: maid-pc"
    echo
    echo "== system =="
    uname -a 2>&1 | redact
    grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release 2>/dev/null | redact
    plasmashell --version 2>/dev/null | head -n 1
    pipewire --version 2>/dev/null | head -n 1
    echo
    echo "== check =="
    bash "$0" check 2>&1
    echo
    echo "== rfkill =="
    rfkill list bluetooth 2>&1 | redact
    echo
    echo "== bluetooth adapter =="
    bluetoothctl show 2>&1 | redact
    echo
    echo "== connected devices =="
    bluetoothctl devices Connected 2>&1 | redact
    echo
    echo "== audio =="
    pactl info 2>&1 | redact
    printf '\n'
    pactl list short sinks 2>&1 | redact
    echo
    echo "== user services =="
    systemctl --user status buds-fallback.service maid-watcher.service --no-pager -l 2>&1 | redact
    echo
    echo "== config (MACs redacted) =="
    [ -f "$CONF" ] && cat "$CONF" | redact
    [ -f "$WCONF" ] && cat "$WCONF" | redact
    echo
    echo "== recent Maid logs =="
    local f
    for f in "$LOGDIR"/*.log; do
      [ -f "$f" ] || continue
      echo "--- $(basename "$f") (tail) ---"
      tail -n 80 "$f" 2>&1 | redact
    done
  } > "$report" 2>&1
  echo "REPORT: $report"
  echo
  echo "result: report saved (MACs, home path, and host name redacted)"
  exit 0
}

case "$MODE" in
  check) do_check ;;
  fix) do_fix ;;
  report) do_report ;;
  *) echo "unknown mode: $MODE (use check, fix, or report)" >&2; exit 2 ;;
esac
