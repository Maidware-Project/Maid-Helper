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
if grep -rni -E "AA:BB|RemoteApp|ExampleBuds|Liberty|example-host|10\.0\.0|/home/EXAMPLEUSER/" \
    "$PKGDIR/bin" "$PKGDIR/README.md" "$PKGDIR/CHANGELOG.md" "$PKGDIR/install.sh" 2>/dev/null | grep -v "s|/home/EXAMPLEUSER/|"; then
  fail "personal string leaked"
fi
ok "no personal data"

echo "== installer dry run =="
rm -rf /tmp/maidhelp-t; mkdir -p /tmp/maidhelp-t
HOME=/tmp/maidhelp-t bash "$PKGDIR/install.sh" --check >/dev/null 2>&1 || fail "install --check"
[ -e /tmp/maidhelp-t/.local/bin/maid-helper ] && fail "dry run wrote files"
ok "installer dry run clean"

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

echo "== gpu: no nvidia is healthy, present-but-driverless needs fix =="
export NVIDIA_VGA=0
out=$(bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "0" ] || fail "gpu check should pass without nvidia (rc=$rc)"
export NVIDIA_VGA=1
out=$(bash "$PKGDIR/bin/mod-gpu.sh" check 2>&1); rc=$?
[ "$rc" = "2" ] || fail "gpu check should need fix (rc=$rc)"
out=$(bash "$PKGDIR/bin/mod-gpu.sh" fix </dev/null 2>&1); rc=$?
[ "$rc" = "2" ] || fail "proprietary needs consent (rc=$rc)"
echo "$out" | grep -q "NVIDIA_PROPRIETARY" || fail "consent hint missing"
ok "gpu detect + consent gate"

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
unset FF_DECODERS BT_CODECS NVIDIA_VGA
ok "cleanup"
echo "ALL $PASS PASSED"
