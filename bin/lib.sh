#!/usr/bin/env bash
# Maid Helper shared bits. Sourced by maid-helper and mod-*.sh, never run.
# Expects BINDIR (module dir) and LOG (log file) from the caller.
# shellcheck disable=SC2034
HELPER_LIB_LOADED=1

log() { echo "$*" >> "$LOG"; }
say() { echo "$*"; log "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

detect_pm() {
  # MAID_OS_RELEASE overrides the source (tests feed fixture files).
  # Derivatives ride their family via ID_LIKE (manjaro, pop, mint...).
  # Unknown distros report none — callers print manual commands instead
  # of failing silently.
  local release="${MAID_OS_RELEASE:-/etc/os-release}"
  if [ -f "$release" ]; then
    # shellcheck disable=SC1091
    . "$release"
    case "${ID:-} ${ID_LIKE:-}" in
      *arch*) echo pacman; return ;;
      *debian*|*ubuntu*|*linuxmint*) echo apt; return ;;
      *fedora*|*rhel*|*centos*|*rocky*|*alma*) echo dnf; return ;;
      *suse*|*opensuse*) echo zypper; return ;;
    esac
  fi
  for c in pacman apt-get dnf zypper; do
    if command -v "$c" >/dev/null 2>&1; then
      case "$c" in
        pacman) echo pacman; return ;;
        apt-get) echo apt; return ;;
        dnf) echo dnf; return ;;
        zypper) echo zypper; return ;;
      esac
    fi
  done
  echo none
}

ensure_sudo() {
  # one password prompt up front instead of one per package
  sudo -v || { echo "need sudo for package installs" >&2; return 1; }
}

# consent "prompt" VAR — true if $VAR=1 or a tty says yes. Never true
# non-interactive without the env var (safe default for scripts/CI).
# Used before any non-free software (NVIDIA drivers, MS fonts).
consent() {
  local prompt="$1" var="$2" ans val
  val="${!var:-0}"
  [ "$val" = "1" ] && return 0
  if [ ! -t 0 ]; then
    echo "  (needs $var=1 or an interactive terminal: $prompt)"
    return 1
  fi
  printf '  %s [y/N]: ' "$prompt"
  read -r ans
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# install_pkgs pm pkg... — one call, then honest per-package report.
# echoes INSTALLED/FAILED lines; returns nonzero only if ALL failed.
install_pkgs() {
  local pm="$1"; shift
  [ "$#" -gt 0 ] || return 0
  case "$pm" in
    pacman) sudo pacman -S --needed --noconfirm "$@" ;;
    apt) sudo apt-get update && sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    zypper) sudo zypper --non-interactive install "$@" ;;
    *) echo "unsupported distro — install manually: $*"; return 1 ;;
  esac 2>&1 | tail -n 3
  local p ok=0
  for p in "$@"; do
    if pkg_present "$p"; then
      echo "  installed: $p"; ok=1
    else
      echo "  FAILED: $p (see above; rerun or install by hand)"
    fi
  done
  [ "$ok" = "1" ]
}

pkg_present() {
  # $1 = bare package name; true if the distro's db knows it installed
  case "$(detect_pm)" in
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    apt) dpkg -s "$1" >/dev/null 2>&1 ;;
    dnf) rpm -q "$1" >/dev/null 2>&1 ;;
    zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}
