#!/usr/bin/env bash
# Maid Helper test suite. Stub farm fakes package managers, detectors,
# and sudo — safe anywhere, no root, no network, no real config touched.
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
if grep -rni -E "90:BF|SmartAction|soundcore|Liberty|Mothership|10\.0\.0|/home/visa" \
    "$PKGDIR/bin" "$PKGDIR/README.md" "$PKGDIR/CHANGELOG.md" "$PKGDIR/install.sh" 2>/dev/null | grep -v "s|/home/visa|"; then
  fail "personal string leaked"
fi
ok "no personal data"

echo "== installer dry run =="
rm -rf /tmp/maidhelp-t; mkdir -p /tmp/maidhelp-t
HOME=/tmp/maidhelp-t bash "$PKGDIR/install.sh" --check >/dev/null 2>&1 || fail "install --check"
[ -e /tmp/maidhelp-t/.local/bin/maid-helper ] && fail "dry run wrote files"
ok "installer dry run clean"

echo "== installer covers every module =="
rm -rf /tmp/maidhelp-i; mkdir -p /tmp/maidhelp-i
HOME=/tmp/maidhelp-i bash "$PKGDIR/install.sh" --no-packages </dev/null >/dev/null 2>&1 || fail "fake install crashed"
for f in "$PKGDIR"/bin/mod-*.sh; do
  b=$(basename "$f")
  cmp -s "$f" "/tmp/maidhelp-i/.local/bin/$b" || fail "not installed: $b"
done
[ -x /tmp/maidhelp-i/.local/bin/maid-helper ] || fail "dispatcher not executable"
[ -f /tmp/maidhelp-i/.local/share/applications/maid-helper.desktop ] || fail "desktop entry missing"
HOME=/tmp/maidhelp-i bash "$PKGDIR/install.sh" --uninstall --purge </dev/null >/dev/null 2>&1 || fail "fake uninstall crashed"
[ -e /tmp/maidhelp-i/.local/bin/maid-helper ] && fail "uninstall left files"
rm -rf /tmp/maidhelp-i
ok "installer covers every module + uninstall"

echo "== dispatcher: check reports, unknown rejected =="
export PATH="$STUBS:/usr/bin:/bin"
export HOME=/tmp/maidhelp-t
out=$(bash "$PKGDIR/bin/maid-helper" --check 2>&1)
echo "$out" | grep -q "result:" || fail "no result line"
bash "$PKGDIR/bin/maid-helper" --only bogus --check >/dev/null 2>&1 && fail "bogus module accepted"
ok "dispatcher contract"

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
out=$(bash "$PKGDIR/bin/mod-fonts.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "fonts check should pass (rc=$rc)"
ok "print + fonts detect"

echo "== suite module: missing siblings reported =="
out=$(bash "$PKGDIR/bin/mod-suite.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "suite should need fix in empty home (rc=$rc)"
echo "$out" | grep -q "Maid BT not installed" || fail "bt missing not reported"
ok "suite wholeness"

echo "== cleanup =="
rm -rf /tmp/maidhelp-t
unset FF_DECODERS BT_CODECS NVIDIA_VGA AMD_VGA AMD_RV GAMEPAD FLAT_STATE FW_STATE
ok "cleanup"
echo "ALL $PASS PASSED"
