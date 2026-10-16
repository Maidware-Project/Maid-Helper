#!/usr/bin/env bash
# Maid suite meta-installer: one command for the whole family.
# Clones what's missing, pulls the rest (--ff-only, diverged trees are
# left alone and reported), then runs each project's install.sh.
#   install-suite.sh [--check] [--no-packages] [--pull-only]
# --check: report only, change nothing. --pull-only: update code, skip
# installers. Run in a terminal: per-project installers ask their own
# questions (MAC, opt-ins) when they have a tty.
# "localdir|reponame" pairs: checkout names keep their spaces, GitHub
# repos use hyphens (MHE/Maid-Helper is where Helper lives here).
set -u
set -o pipefail
GITHUB="${MAID_GITHUB:-https://github.com/Maidware-Project}"
if [ -n "${MAID_SUITE_BASE:-}" ]; then
  BASES="$MAID_SUITE_BASE"
else
  BASES="$HOME/Documents/GitHub"
fi
PAIRS="Maid BT|Maid-BT
Maid AU|Maid-AU
Maidshare|Maidshare
MHE/Maid-Helper|Maid-Helper"
CHECK=0; NO_PKGS=""; PULLONLY=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --no-packages) NO_PKGS="--no-packages" ;;
    --pull-only) PULLONLY=1 ;;
    *) echo "unknown option: $a (see header)" >&2; exit 2 ;;
  esac
done

say() { echo "==> $*"; }
BASE=""
[ -d "$BASES" ] && BASE="$BASES"
[ -n "$BASE" ] || { say "no checkout base found ($BASES) — create one first"; exit 2; }
say "base: $BASE"

FAILED=0
# herestring (not a pipe) so the loop shares our shell: FAILED propagates.
# (a piped loop runs in a subshell and swallows it.)
while read -r pair; do
  [ -n "$pair" ] || continue
  dlocaldir="${pair%%|*}"
  drepo="${pair##*|}"
  d="$BASE/$dlocaldir"
  if [ ! -d "$d/.git" ]; then
    if [ -e "$d" ]; then
      say "$dlocaldir: not a git checkout — left alone (move it aside to clone fresh)"
      continue
    fi
    say "$dlocaldir: cloning..."
    [ "$CHECK" = "1" ] && { say "(check: would clone $drepo)"; continue; }
    if git clone "$GITHUB/$drepo.git" "$d" 2>&1 | tail -n 1; then
      say "$dlocaldir: cloned."
    else
      say "$dlocaldir: CLONE FAILED (offline? wrong remote?)"
      FAILED=1
      continue
    fi
  else
    if [ "$CHECK" = "1" ]; then
      # check never touches the worktree (fetch only moves remote refs,
      # same contract as Maid AU's own --check).
      if ! git -C "$d" fetch --quiet 2>/dev/null; then
        say "$dlocaldir: offline? (fetch failed)"
        continue
      fi
      behind=$(git -C "$d" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
      if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
        say "$dlocaldir: $behind commit(s) behind."
      else
        say "$dlocaldir: up to date."
      fi
      continue
    fi
    pullout=$(git -C "$d" pull --ff-only 2>&1); pullrc=$?
    if [ "$pullrc" = "0" ]; then
      if echo "$pullout" | grep -qiE "already up to date"; then
        say "$dlocaldir: up to date."
      else
        say "$dlocaldir: updated."
      fi
    else
      say "$dlocaldir: diverged or offline — left alone (pull by hand)."
      continue
    fi
    [ "$CHECK" = "1" ] && continue
  fi
  [ "$PULLONLY" = "1" ] && continue
  if [ -x "$d/install.sh" ]; then
    say "$dlocaldir: installing..."
    # shellcheck disable=SC2086
    if bash "$d/install.sh" $NO_PKGS 2>&1 | tail -n 2; then
      say "$dlocaldir: installed."
    else
      say "$dlocaldir: INSTALLER FAILED — run bash $d/install.sh by hand."
      FAILED=1
    fi
  else
    say "$dlocaldir: no install.sh — skipping."
  fi
done <<< "$PAIRS"
[ "$FAILED" = "0" ] && say "suite done." || { say "suite finished WITH FAILURES (see above)."; exit 1; }
