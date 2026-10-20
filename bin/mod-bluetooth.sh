#!/usr/bin/env bash
# Doctor: Maid BT / Bluetooth troubleshooting (Maid BT Helper backend).
# Detect: bluez service, rfkill, adapter power, earbud config, fallback sink,
# PipeWire/Pulse, Maid BT user services, WirePlumber quality config, and
# recent audit-log errors. Fix: only the safe, local parts (service/rfkill/
# adapter/user units). MAC and sink choices stay manual.
# Usage: mod-bluetooth.sh check|fix|quality|report
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
    -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/AA:BB:CC:DD:EE:FF/g' \
    -e 's/([0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2}/AA_BB_CC_DD_EE_FF/g'
}

conf_get() {
  local key="$1"
  [ -f "$CONF" ] || return 0
  sed -n -E "s/^[[:space:]]*${key}=[\"']?([^\"']*)[\"']?[[:space:]]*$/\1/p" "$CONF" | tail -n 1
}

card_name() {
  pactl list short cards 2>/dev/null | awk '/bluez_card/{print $2; exit}'
}

buds_connected() {
  local mac
  mac=$(conf_get BUDS_MAC)
  [ -n "$mac" ] || return 1
  bluetoothctl info "$mac" 2>/dev/null | grep -q 'Connected: yes'
}

active_profile() {
  local card
  card=$(card_name)
  [ -n "$card" ] || return 0
  pactl list cards 2>/dev/null \
    | awk -v c="$card" '$0 ~ ("Name: " c) {p=1}
        p && /Active Profile:/ {sub(/^[^:]*: /, ""); print; exit}'
}

bt_codec() {
  pactl list sinks 2>/dev/null \
    | awk '/Name: bluez_output/{p=1}
        p && /api.bluez5.codec/ {gsub(/.*= "/, ""); gsub(/".*/, ""); print; exit}'
}

default_sink() {
  pactl info 2>/dev/null | sed -n 's/^Default Sink: //p' | head -n 1
}

mic_busy() {
  # A live call/recording owns a capture stream; never yank it to A2DP.
  pactl list source-outputs 2>/dev/null | grep -q 'Corked: no'
}

toggle_bin() {
  local t
  for t in "$HOME/.local/bin/bluetooth-toggle.sh" /usr/bin/bluetooth-toggle.sh; do
    [ -x "$t" ] && { printf '%s\n' "$t"; return 0; }
  done
  command -v bluetooth-toggle.sh 2>/dev/null || true
}

quality_conf() {
  printf '%s\n' "$HOME/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf"
}

write_quality_config() {
  local dest src=""
  dest=$(quality_conf)
  mkdir -p "$(dirname "$dest")" || return 1
  for src in "$HOME/.local/share/maid-bt/52-bt-max-quality.conf" \
             "/usr/share/maid-bt/52-bt-max-quality.conf"; do
    [ -f "$src" ] && break
    src=""
  done
  if [ -n "$src" ]; then
    cp -a "$src" "$dest"
  else
    cat > "$dest" <<'EOF'
# Maid BT: prefer LDAC, then AAC, high-bitpool SBC (XQ), stock SBC last.
monitor.bluez.properties = {
  bluez5.codecs = [ ldac aac sbc_xq sbc ]
  bluez5.enable-sbc-xq = true
}
EOF
  fi
}

set_quality_lock() {
  local tmp
  [ -f "$CONF" ] || return 1
  tmp=$(mktemp) || return 1
  awk '
    BEGIN { done = 0 }
    /^[[:space:]]*QUALITY_LOCK[[:space:]]*=/ {
      print "QUALITY_LOCK=1"; done = 1; next
    }
    { print }
    END { if (!done) print "QUALITY_LOCK=1" }
  ' "$CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
  cp -a "$CONF" "$CONF.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  chmod --reference="$CONF" "$tmp" 2>/dev/null || true
  mv "$tmp" "$CONF"
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

  if buds_connected; then
    local out
    out=$(default_sink)
    if printf '%s\n' "$out" | grep -q '^bluez'; then
      echo "OK - earbuds are the current audio output"
    else
      echo "NEEDS FIX - earbuds are connected but audio is routed elsewhere"
      echo "  why: this is the 'connected but I hear nothing' state"
      NEED=1
    fi
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
  local profile codec lock conf
  conf=$(quality_conf)
  lock=$(conf_get QUALITY_LOCK)
  if have pactl; then
    profile=$(active_profile)
    codec=$(bt_codec)
  fi

  if have pactl && buds_connected; then
    case "$profile" in
      headset-head-unit*)
        if mic_busy; then
          echo "OK - call profile is active because the microphone is in use"
        else
          echo "NEEDS FIX - thin headset/call profile is active with no microphone in use"
          NEED=1
        fi
        ;;
      a2dp-sink*)
        if [ -n "$codec" ]; then
          echo "OK - playback profile: a2dp ($codec)"
        else
          echo "OK - playback profile: a2dp"
        fi
        case "$codec" in
          sbc)
            echo "NOTE - SBC is active; Fix sound quality can prefer LDAC/AAC/SBC-XQ"
            ;;
          ldac)
            echo "OK - LDAC is active"
            ;;
        esac
        ;;
      "")
        echo "NOTE - earbuds are connected, but the audio card is not ready yet"
        ;;
    esac
  else
    echo "NOTE - earbuds are not connected; codec check skipped"
  fi

  if [ "$lock" = "1" ]; then
    if [ -f "$conf" ]; then
      echo "OK - quality lock is on and the max-quality config is installed"
    else
      echo "NEEDS FIX - quality lock is on but the max-quality WirePlumber config is missing"
      NEED=1
    fi
  else
    echo "NOTE - quality lock is off (LDAC is still offered when available)"
    [ -f "$conf" ] && echo "NOTE - max-quality config is present; set QUALITY_LOCK=1 to enforce LDAC after switches"
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

  if [ "$(conf_get QUALITY_LOCK)" = "1" ] && [ ! -f "$(quality_conf)" ]; then
    echo "- installing the max-quality WirePlumber config"
    if write_quality_config; then
      systemctl --user restart wireplumber.service 2>/dev/null || true
    else
      echo "!! could not write the max-quality config"
    fi
  fi

  if buds_connected; then
    local out toggle
    out=$(default_sink)
    if ! printf '%s\n' "$out" | grep -q '^bluez'; then
      toggle=$(toggle_bin)
      if [ -n "$toggle" ]; then
        echo "- routing audio back to the earbuds"
        timeout 45 "$toggle" on 2>&1 | tail -n 15 || true
      else
        echo "!! bluetooth-toggle.sh not found; reinstall Maid BT"
      fi
    fi
  fi

  echo
  echo "Manual steps are printed as comments; nothing here changes your MAC or speaker choice."
  echo "Rechecking..."
  echo
  do_check
}

do_quality() {
  echo "Improving Bluetooth sound quality..."
  echo
  echo "- installing the max-quality WirePlumber config (LDAC -> AAC -> SBC-XQ -> SBC)"
  if write_quality_config; then
    echo "  written: $(quality_conf)"
  else
    echo "!! could not write the max-quality config"
    exit 1
  fi

  if [ ! -f "$CONF" ]; then
    echo "!! Maid BT config is missing; run the Maid BT installer first"
    exit 1
  fi
  echo "- enabling QUALITY_LOCK=1"
  if ! set_quality_lock; then
    echo "!! could not update $CONF"
    exit 1
  fi
  echo "  backed up the old config next to it"

  echo "- restarting WirePlumber to load the codec ladder"
  systemctl --user restart wireplumber.service 2>/dev/null || true

  if ! buds_connected; then
    echo
    echo "NOTE - earbuds are not connected; the settings are ready for next time."
  elif mic_busy; then
    echo
    echo "NOTE - a call or recording is using the microphone; not switching to A2DP now."
  else
    local toggle
    toggle=$(toggle_bin)
    echo
    if [ -n "$toggle" ]; then
      echo "- switching the earbuds back to A2DP / LDAC"
      timeout 60 "$toggle" on 2>&1 | tail -n 20 || true
    else
      echo "!! bluetooth-toggle.sh not found; reinstall Maid BT"
    fi
  fi

  echo
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
  quality) do_quality ;;
  report) do_report ;;
  *) echo "unknown mode: $MODE (use check, fix, quality, or report)" >&2; exit 2 ;;
esac
