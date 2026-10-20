#!/usr/bin/env bash
# Maid Helper test suite. Stub farm fakes package managers, detectors,
# and sudo - safe anywhere, no root, no network, no real config touched.
# Exit nonzero on first failure.
set -u
PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"
STUBS="$PKGDIR/tests/stubs"
PASS=0
ok()   { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
fail() { echo "NOT OK - $1"; exit 1; }

echo "== syntax =="
for f in "$PKGDIR"/bin/*.sh "$PKGDIR"/install.sh; do
  bash -n "$f" || fail "bash -n $f"
done
command -v shellcheck >/dev/null 2>&1 && shellcheck -S error "$PKGDIR"/bin/*.sh "$PKGDIR"/install.sh || true
ok "syntax"

echo "== personal data =="
if grep -rn --exclude-dir=__pycache__ -iE "([0-9a-f]{2}:){5}[0-9a-f]{2}|/(home|Users)/[^/[:space:]]+|(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}" \
    "$PKGDIR/bin" "$PKGDIR/desktop" "$PKGDIR/README.md" "$PKGDIR/CHANGELOG.md" "$PKGDIR/install.sh" 2>/dev/null \
    | grep -v "AA:BB:CC:DD:EE:FF"; then
  fail "personal string leaked"
fi
ok "no personal data"

echo "== installer dry run =="
rm -rf /tmp/maidhelp-t; mkdir -p /tmp/maidhelp-t
out=$(HOME=/tmp/maidhelp-t bash "$PKGDIR/install.sh" --check 2>&1) || fail "install --check"
echo "$out" | grep -q '^==> KDE:' || fail "installer does not report the KDE stack"
[ -e /tmp/maidhelp-t/.local/bin/maid-helper ] && fail "dry run wrote files"
ok "installer dry run clean"

echo "== installer covers every module =="
rm -rf /tmp/maidhelp-i; mkdir -p /tmp/maidhelp-i/.local/share/maid-helper/patches
touch /tmp/maidhelp-i/.local/share/maid-helper/patches/old.patch
HOME=/tmp/maidhelp-i bash "$PKGDIR/install.sh" --no-packages </dev/null >/dev/null 2>&1 || fail "fake install crashed"
for f in "$PKGDIR"/bin/mod-*.sh; do
  b=$(basename "$f")
  cmp -s "$f" "/tmp/maidhelp-i/.local/bin/$b" || fail "not installed: $b"
done
cmp -s "$PKGDIR/bin/kde-env.sh" "/tmp/maidhelp-i/.local/bin/kde-env.sh" || fail "not installed: kde-env.sh"
[ -e /tmp/maidhelp-i/.local/share/maid-helper/patches ] && fail "legacy patch dir not cleaned"
[ -x /tmp/maidhelp-i/.local/bin/maid-helper ] || fail "dispatcher not executable"
[ -x /tmp/maidhelp-i/.local/bin/maid-helper-run ] || fail "launcher not executable"
[ -f /tmp/maidhelp-i/.local/share/applications/maid-helper.desktop ] || fail "desktop entry missing"
[ -f /tmp/maidhelp-i/.local/share/icons/hicolor/scalable/apps/maid-helper.svg ] || fail "icon missing"
grep -q "Terminal=false" /tmp/maidhelp-i/.local/share/applications/maid-helper.desktop || fail "desktop forces terminal"
HOME=/tmp/maidhelp-i bash "$PKGDIR/install.sh" --uninstall --purge </dev/null >/dev/null 2>&1 || fail "fake uninstall crashed"
[ -e /tmp/maidhelp-i/.local/bin/maid-helper ] && fail "uninstall left files"
[ -e /tmp/maidhelp-i/.local/bin/kde-env.sh ] && fail "uninstall left kde-env.sh"
[ -e /tmp/maidhelp-i/.local/share/icons/hicolor/scalable/apps/maid-helper.svg ] && fail "uninstall left icon"
[ -e /tmp/maidhelp-i/.local/bin/maid-helper-run ] && fail "uninstall left launcher"
rm -rf /tmp/maidhelp-i
ok "installer covers every module + uninstall"

echo "== launcher: dead default skipped, window stays, args passed =="
rm -f /tmp/mh-term.log
HOME=/tmp/maidhelp-t PATH="$STUBS:/usr/bin:/bin" bash "$PKGDIR/bin/maid-helper-run" --only suite --check > /tmp/mh-term-out.txt 2>&1
grep -q "TERM_LAUNCH: -e .*maid-helper" /tmp/mh-term.log || fail "launcher did not fall back to a real terminal"
grep -q "TERM_ARGS: --only suite --check" /tmp/mh-term.log || fail "launcher arguments did not reach the helper"
grep -q "press enter to close" /tmp/mh-term.log || fail "launcher window would close instantly"
grep -q "safe fixes" /tmp/mh-term.log || fail "launcher does not offer the fixes"
rm -f /tmp/mh-term.log
FAKE_TERMAPP=myterm HOME=/tmp/maidhelp-t PATH="$STUBS:/usr/bin:/bin" bash "$PKGDIR/bin/maid-helper-run" --only suite --check > /tmp/mh-term-out.txt 2>&1
grep -q "MYTERM: -e .*maid-helper" /tmp/mh-term.log || fail "usable desktop default ignored"
last_args=$(grep "TERM_ARGS:" /tmp/mh-term.log | tail -n 1)
[ "$last_args" = "TERM_ARGS: --only suite --check" ] || fail "usable desktop default lost the arguments"
rm -f /tmp/mh-term.log /tmp/mh-term-out.txt
ok "launcher picks terminal"

echo "== dispatcher: check reports, unknown rejected, run logged =="
export PATH="$STUBS:/usr/bin:/bin"
export HOME=/tmp/maidhelp-t
export MAID_KDECONNECTD=/nonexistent
out=$(bash "$PKGDIR/bin/maid-helper" --check 2>&1)
echo "$out" | grep -q "result:" || fail "no result line"
[ -s /tmp/maidhelp-t/.local/share/maid-helper.log ] || fail "run log not written"
grep -q "^===== maid-helper check " /tmp/maidhelp-t/.local/share/maid-helper.log || fail "log missing run header"
grep -q -- "--- codecs ---" /tmp/maidhelp-t/.local/share/maid-helper.log || fail "log missing module output"
bash "$PKGDIR/bin/maid-helper" --only bogus --check >/dev/null 2>&1 && fail "bogus module accepted"
ok "dispatcher contract"

echo "== kdeconnect: wrapper installs into a fake home =="
rm -rf /tmp/maidhelp-kc /tmp/maidhelp-kc-bin
mkdir -p /tmp/maidhelp-kc /tmp/maidhelp-kc-bin
printf '#!/bin/sh\nexit 0\n' > /tmp/maidhelp-kc-bin/kdeconnectd
chmod +x /tmp/maidhelp-kc-bin/kdeconnectd
export HOME=/tmp/maidhelp-kc
export MAID_KDECONNECTD=/tmp/maidhelp-kc-bin/kdeconnectd
out=$(PATH="$STUBS:/usr/bin:/bin" bash "$PKGDIR/bin/mod-kdeconnect.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "kdeconnect check should need fix (rc=$rc): $out"
echo "$out" | grep -q '^KDE:' || fail "kdeconnect doctor does not report the KDE stack"
out=$(PATH="$STUBS:/usr/bin:/bin" bash "$PKGDIR/bin/mod-kdeconnect.sh" fix 2>&1); rc=$?
[ "$rc" = "0" ] || fail "kdeconnect fix failed (rc=$rc): $out"
[ -x "$HOME/.local/bin/kdeconnectd-wrapper" ] || fail "wrapper not installed"
grep -q 'QT_QPA_PLATFORM' "$HOME/.local/bin/kdeconnectd-wrapper" || fail "wrapper missing platform fallback"
grep -q 'kdeconnect-bin' "$HOME/.local/bin/kdeconnectd-wrapper" || fail "wrapper missing sshfs shim path"
[ -x "$HOME/.local/lib/maid-helper/kdeconnect-bin/sshfs" ] || fail "sshfs shim not installed"
grep -q 'storage/emulated/0' "$HOME/.local/lib/maid-helper/kdeconnect-bin/sshfs" || fail "sshfs shim missing Android storage root"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > /tmp/maidhelp-kc-sshfs.args\n' > /tmp/maidhelp-kc-bin/sshfs-real
chmod +x /tmp/maidhelp-kc-bin/sshfs-real
MAID_SSHFS_REAL=/tmp/maidhelp-kc-bin/sshfs-real \
  "$HOME/.local/lib/maid-helper/kdeconnect-bin/sshfs" \
  'kdeconnect@192.0.2.10:/' /tmp/maidhelp-kc-mnt -p 2222
grep -Fqx 'kdeconnect@192.0.2.10:/storage/emulated/0' /tmp/maidhelp-kc-sshfs.args || fail "sshfs shim did not remap root"
grep -Fqx '/tmp/maidhelp-kc-mnt' /tmp/maidhelp-kc-sshfs.args || fail "sshfs shim lost mountpoint"
grep -Fqx -- '-p' /tmp/maidhelp-kc-sshfs.args || fail "sshfs shim lost options"
rm -f /tmp/maidhelp-kc-sshfs.args
MAID_SSHFS_REAL=/tmp/maidhelp-kc-bin/sshfs-real \
  "$HOME/.local/lib/maid-helper/kdeconnect-bin/sshfs" \
  'kdeconnect@192.0.2.10:/storage/emulated/0/Download' /tmp/maidhelp-kc-mnt
grep -Fqx 'kdeconnect@192.0.2.10:/storage/emulated/0/Download' /tmp/maidhelp-kc-sshfs.args || fail "sshfs shim rewrote a supplied path"
rm -f /tmp/maidhelp-kc-sshfs.args
grep -Fqx "Exec=$HOME/.local/bin/kdeconnectd-wrapper" "$HOME/.local/share/dbus-1/services/org.kde.kdeconnect.service" || fail "dbus override missing"
grep -Fqx "Exec=$HOME/.local/bin/kdeconnectd-wrapper" "$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop" || fail "autostart override missing"
out=$(PATH="$STUBS:/usr/bin:/bin" bash "$PKGDIR/bin/mod-kdeconnect.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "kdeconnect check still failing after fix (rc=$rc): $out"
rm -rf /tmp/maidhelp-kc /tmp/maidhelp-kc-bin
ok "kdeconnect wrapper"

echo "== codecs: missing decoders need fix, bt card assessed =="
export FF_DECODERS=none BT_CODECS=full
out=$(bash "$PKGDIR/bin/mod-codecs.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "codecs check should need fix (rc=$rc)"
echo "$out" | grep -q "NEEDS FIX" || fail "no needs-fix line"
export FF_DECODERS=full
out=$(bash "$PKGDIR/bin/mod-codecs.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "codecs check should pass (rc=$rc)"
echo "$out" | grep -q "LDAC + AAC" || fail "bt codec ladder not confirmed"
export BT_CODECS=none
out=$(bash "$PKGDIR/bin/mod-codecs.sh" check 2>&1)
echo "$out" | grep -q "skip - no bluetooth" || fail "no-card skip missing"
ok "codecs detect"

echo "== gpu: nouveau + amdgpu healthy paths =="
export NVIDIA_VGA=0 AMD_VGA=0
out=$(bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "gpu check should pass with no GPU (rc=$rc)"
export NVIDIA_VGA=1
mkdir -p /tmp/mh-modprobe && : > /tmp/mh-modprobe/empty.conf
printf '' > /tmp/mh-cmdline
out=$(MAID_MODPROBE_D=/tmp/mh-modprobe MAID_CMDLINE=/tmp/mh-cmdline bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "nouveau healthy should pass (rc=$rc): $out"
echo "$out" | grep -q "Nouveau driving" || fail "nouveau ok line missing"
export NVIDIA_VGA=0 AMD_VGA=1 MAID_VULKAN_DIR=/tmp/mh-vk
mkdir -p /tmp/mh-vk && : > /tmp/mh-vk/radeon_icd.x86_64.json
out=$(bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "amdgpu healthy should pass (rc=$rc): $out"
echo "$out" | grep -q "amdgpu driving" || fail "amdgpu ok line missing"
ok "gpu nouveau + amdgpu healthy"

echo "== gpu: nouveau blacklisted, radeon legacy need fix =="
export NVIDIA_VGA=1 AMD_VGA=0
printf 'blacklist nouveau\n' > /tmp/mh-modprobe/nvidia.conf
out=$(MAID_MODPROBE_D=/tmp/mh-modprobe MAID_CMDLINE=/tmp/mh-cmdline bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "blacklisted nouveau should need fix (rc=$rc)"
out=$(MAID_MODPROBE_D=/tmp/mh-modprobe MAID_CMDLINE=/tmp/mh-cmdline bash "$PKGDIR/bin/mod-gpu.sh" fix </dev/null 2>&1); rc=$?
[ "$rc" = "2" ] || fail "blacklist fix ends reboot-pending (rc=$rc)"
grep -q "^# maid-helper disabled: blacklist nouveau" /tmp/mh-modprobe/nvidia.conf || fail "blacklist not commented"
[ -f /tmp/mh-modprobe/nvidia.conf.maid-bak ] || fail "no backup of modprobe file"
export NVIDIA_VGA=0 AMD_VGA=1 AMD_RV=1
out=$(bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "radeon legacy should need fix (rc=$rc)"
echo "$out" | grep -q "amdgpu.si_support=1" || fail "kernel flags not printed"
rm -rf /tmp/mh-modprobe /tmp/mh-cmdline /tmp/mh-vk
ok "gpu blacklist + legacy need fix"

echo "== distros: derivatives ride their family =="
[ "$(PKGDIR="$PKGDIR" MAID_OS_RELEASE="$PKGDIR/tests/fixtures/os-manjaro" bash -c '. "$PKGDIR/bin/lib.sh"; detect_pm')" = "pacman" ] || fail "manjaro not pacman"
[ "$(PKGDIR="$PKGDIR" MAID_OS_RELEASE="$PKGDIR/tests/fixtures/os-pop" bash -c '. "$PKGDIR/bin/lib.sh"; detect_pm')" = "apt" ] || fail "pop not apt"
[ "$(PKGDIR="$PKGDIR" MAID_OS_RELEASE="$PKGDIR/tests/fixtures/os-mint" bash -c '. "$PKGDIR/bin/lib.sh"; detect_pm')" = "apt" ] || fail "mint not apt"
[ "$(PKGDIR="$PKGDIR" MAID_OS_RELEASE="$PKGDIR/tests/fixtures/os-rocky" bash -c '. "$PKGDIR/bin/lib.sh"; detect_pm')" = "dnf" ] || fail "rocky not dnf"
mkdir -p /tmp/mh-nopm
[ "$(PKGDIR="$PKGDIR" MAID_OS_RELEASE="$PKGDIR/tests/fixtures/os-void" PATH=/tmp/mh-nopm "$BASH" -c '. "$PKGDIR/bin/lib.sh"; detect_pm')" = "none" ] || fail "void should be none"
[ "$(PKGDIR="$PKGDIR" MAID_OS_RELEASE="$PKGDIR/tests/fixtures/os-nixos" PATH=/tmp/mh-nopm "$BASH" -c '. "$PKGDIR/bin/lib.sh"; detect_pm')" = "none" ] || fail "nixos should be none"
rm -rf /tmp/mh-nopm
ok "distro families"

echo "== gamepad: none healthy, usb/bt need fix =="
export GAMEPAD=none
out=$(bash "$PKGDIR/bin/mod-gamepad.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "no gamepad should pass (rc=$rc)"
export GAMEPAD=usb
out=$(bash "$PKGDIR/bin/mod-gamepad.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "usb pad should need fix (rc=$rc)"
echo "$out" | grep -q "Steam Input" || fail "steam note missing"
export GAMEPAD=bt
out=$(bash "$PKGDIR/bin/mod-gamepad.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "bt pad should need fix (rc=$rc)"
ok "gamepad detect"

echo "== flatpak + firmware =="
export FLAT_STATE=/tmp/mh-flat; : > /tmp/mh-flat
out=$(bash "$PKGDIR/bin/mod-flatpak.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "missing flathub should need fix (rc=$rc)"
out=$(bash "$PKGDIR/bin/mod-flatpak.sh" fix 2>&1); rc=$?
[ "$rc" = "0" ] || fail "flathub fix should pass (rc=$rc): $out"
grep -q flathub /tmp/mh-flat || fail "remote not recorded"
rm -f /tmp/mh-flat
export FW_STATE=missing
out=$(bash "$PKGDIR/bin/mod-firmware.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "missing fwupd should need fix (rc=$rc)"
out=$(bash "$PKGDIR/bin/mod-firmware.sh" fix 2>&1); rc=$?
[ "$rc" = "1" ] || fail "broken fwupd fix should fail honestly (rc=$rc)"
echo "$out" | grep -q "FAILED - fwupd" || fail "fwupd failure not reported"
export FW_STATE=ok
out=$(bash "$PKGDIR/bin/mod-firmware.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "fwupd present should pass (rc=$rc)"
ok "flatpak + firmware"

echo "== print + fonts: healthy paths =="
out=$(bash "$PKGDIR/bin/mod-print.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "print check should pass (rc=$rc)"
out=$(FAKE_DEFAULT=none bash "$PKGDIR/bin/mod-print.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "print check with no default printer should pass (rc=$rc)"
echo "$out" | grep -q "no default printer" || fail "no-default-printer note missing"
out=$(bash "$PKGDIR/bin/mod-fonts.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "fonts check should pass (rc=$rc)"
ok "print + fonts detect"

echo "== suite module: missing siblings reported =="
out=$(bash "$PKGDIR/bin/mod-suite.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "suite should need fix in empty home (rc=$rc)"
echo "$out" | grep -q "Maid BT not installed" || fail "bt missing not reported"
ok "suite wholeness"

echo "== suite spine: check plans without touching =="
rm -rf /tmp/mh-base; mkdir -p "/tmp/mh-base/Maid BT"
git init -q "/tmp/mh-base/Maid BT" 2>/dev/null
printf '#!/bin/bash\necho stub-install\n' > "/tmp/mh-base/Maid BT/install.sh"
chmod +x "/tmp/mh-base/Maid BT/install.sh"
mkdir -p "/tmp/mh-base/plaindir"
out=$(MAID_SUITE_BASE=/tmp/mh-base MAID_GITHUB=/tmp/mh-base bash "$PKGDIR/install-suite.sh" --check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "spine check crashed (rc=$rc)"
echo "$out" | grep -q "Maid AU: cloning..." || fail "missing spaced repo not planned"
echo "$out" | grep -q "(check: would clone Maid-AU)" || fail "clone target wrong"
echo "$out" | grep -q "MHE/Maid-Helper: cloning..." || fail "nested repo not planned"
echo "$out" | grep -qE "^==> Maid: " && fail "spaced names shredded!"
[ -d "/tmp/mh-base/Maid AU" ] && fail "check mode cloned!"
rm -rf /tmp/mh-base
ok "suite spine check"

echo "== bluetooth quality fix =="
rm -rf /tmp/maidhelp-bt && mkdir -p /tmp/maidhelp-bt/stubs /tmp/maidhelp-bt/.config \
  /tmp/maidhelp-bt/.local/bin /tmp/maidhelp-bt/.local/share/maid-bt /tmp/maidhelp-bt/run
cat > /tmp/maidhelp-bt/stubs/bluetoothctl <<'EOF'
#!/bin/bash
case "$*" in
  *show*) echo "Controller AA:BB:CC:DD:EE:FF"; echo "Powered: yes" ;;
  *info*) echo "Device 11:22:33:44:55:66"; echo "Connected: yes" ;;
  *) exit 0 ;;
esac
EOF
cat > /tmp/maidhelp-bt/stubs/pactl <<'EOF'
#!/bin/bash
case "$*" in
  info) echo "Server Name: PulseAudio (on PipeWire 1.0)"; echo "Default Sink: bluez_output.11_22_33_44_55_66.1" ;;
  "list short cards") echo "99 bluez_card.11_22_33_44_55_66 module-bluez5-device.c" ;;
  "list short sinks") printf '50\tbluez_output.11_22_33_44_55_66.1\n51\talsa_output.fallback\n' ;;
  "list short sink-inputs") : ;;
  "list source-outputs") : ;;
  "list cards") printf 'Card #99\n\tName: bluez_card.11_22_33_44_55_66\n\tActive Profile: a2dp-sink\n' ;;
  "list sinks") printf 'Sink #50\n\tName: bluez_output.11_22_33_44_55_66.1\n\tapi.bluez5.codec = "sbc"\n' ;;
  *) : ;;
esac
EOF
printf '#!/bin/bash\nexit 0\n' > /tmp/maidhelp-bt/stubs/rfkill
cat > /tmp/maidhelp-bt/stubs/systemctl <<'EOF'
#!/bin/bash
case "$*" in
  *is-active*) exit 0 ;;
  *list-unit-files*) : ;;
  *) exit 0 ;;
esac
EOF
cat > /tmp/maidhelp-bt/.local/bin/bluetooth-toggle.sh <<'EOF'
#!/bin/bash
echo "toggle $*" >> "$HOME/toggle.calls"
exit 0
EOF
cat > /tmp/maidhelp-bt/.local/bin/buds-fallback.sh <<'EOF'
#!/bin/bash
exit 0
EOF
printf '# source\n' > /tmp/maidhelp-bt/.local/share/maid-bt/52-bt-max-quality.conf
printf 'BUDS_MAC="11:22:33:44:55:66"\nFALLBACK_SINK="alsa_output.fallback"\nQUALITY_LOCK=0\n' > /tmp/maidhelp-bt/.config/bluetooth-buds.conf
chmod +x /tmp/maidhelp-bt/stubs/* /tmp/maidhelp-bt/.local/bin/*.sh
out=$(HOME=/tmp/maidhelp-bt XDG_RUNTIME_DIR=/tmp/maidhelp-bt/run \
  PATH="/tmp/maidhelp-bt/stubs:$STUBS:/usr/bin:/bin" \
  bash "$PKGDIR/bin/maid-helper" --quality 2>&1); rc=$?
[ "$rc" = "0" ] || fail "quality fix failed (rc=$rc): $out"
grep -q 'QUALITY_LOCK=1' /tmp/maidhelp-bt/.config/bluetooth-buds.conf || fail "quality lock not enabled"
[ -f /tmp/maidhelp-bt/.config/wireplumber/wireplumber.conf.d/52-bt-max-quality.conf ] || fail "max-quality config not written"
[ -s /tmp/maidhelp-bt/toggle.calls ] || fail "quality fix did not switch back to A2DP"
grep -q 'Improving Bluetooth sound quality' <<<"$out" || fail "quality output missing"
rm -rf /tmp/maidhelp-bt
ok "bluetooth quality fix"

echo "== cleanup =="
rm -rf /tmp/maidhelp-t
unset FF_DECODERS BT_CODECS NVIDIA_VGA AMD_VGA AMD_RV GAMEPAD FLAT_STATE FW_STATE
ok "cleanup"
echo "ALL $PASS PASSED"
