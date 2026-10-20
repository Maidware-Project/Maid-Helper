#!/usr/bin/env bash
# Universal installer: Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf),
# openSUSE (zypper). Copies files (no symlinks - survives folder moves).
# Usage: ./install.sh [--check] [--no-packages] [--no-gui]
#          [--uninstall [--purge]] [--prefix=DIR] [--no-config]
# --prefix installs program files elsewhere (packaging: DESTDIR supported);
# user setup is skipped for non-default prefixes and with --no-config.
set -u
PKGDIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
CHECK=0; NO_PKGS=0; UNINST=0; PURGE=0; NOCONFIG=0; PREFIX=""; NO_GUI=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --no-packages) NO_PKGS=1 ;;
    --no-gui) NO_GUI=1 ;;
    --uninstall) UNINST=1 ;;
    --purge) PURGE=1 ;;
    --no-config) NOCONFIG=1 ;;
    --prefix=*) PREFIX="${a#--prefix=}" ;;
    *) echo "unknown option: $a (see header)" >&2; exit 2 ;;
  esac
done
if [ -z "$PREFIX" ]; then PREFIX="$HOME/.local"; fi
if [ "$PREFIX" = "$HOME/.local" ]; then
  BINDIR="$HOME/.local/bin"; SHAREDIR="$HOME/.local/share"; REWRITE=1
else
  BINDIR="${DESTDIR:-}$PREFIX/bin"; SHAREDIR="${DESTDIR:-}$PREFIX/share"; REWRITE=2
  NOCONFIG=1
fi

say()  { echo "==> $*"; }
warn() { echo "!! $*" >&2; }

if [ "$UNINST" = "1" ]; then
  # program files come out of the same dirs the install used, so
  # --prefix/DESTDIR installs uninstall cleanly too.
  rm -f "$BINDIR"/maid-helper "$BINDIR"/lib.sh \
    "$BINDIR"/maid-helper-run "$BINDIR"/maid-helper-launch "$BINDIR"/maid-helper-gui \
    "$BINDIR"/mod-codecs.sh "$BINDIR"/mod-gpu.sh \
    "$BINDIR"/mod-print.sh "$BINDIR"/mod-fonts.sh "$BINDIR"/mod-suite.sh \
    "$BINDIR"/mod-gamepad.sh "$BINDIR"/mod-flatpak.sh "$BINDIR"/mod-firmware.sh \
    "$BINDIR"/mod-kdeconnect.sh "$BINDIR"/kde-env.sh "$BINDIR"/mod-bluetooth.sh
  rm -rf "$SHAREDIR"/maid-helper/patches
  rm -f "$SHAREDIR"/applications/maid-helper.desktop
  rm -f "$SHAREDIR"/icons/hicolor/scalable/apps/maid-helper.svg
  if [ "$PURGE" = "1" ]; then
    rm -f "$HOME"/.local/share/maid-helper.log
    say "uninstalled, logs removed (--purge)"
  elif [ -t 0 ]; then
    printf 'Remove the run log too (~/.local/share/maid-helper.log)? [y/N]: '
    read -r _ans
    case "$_ans" in [Yy]*)
      rm -f "$HOME"/.local/share/maid-helper.log
      say "uninstalled, log removed" ;;
    *) say "uninstalled, log kept" ;;
    esac
  else
    say "uninstalled (kept: ~/.local/share/maid-helper.log; rerun with --purge to remove)"
  fi
  exit 0
fi

detect_pm() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-} ${ID_LIKE:-}" in
      *arch*) echo pacman; return ;;
      *debian*|*ubuntu*|*linuxmint*) echo apt; return ;;
      *fedora*|*rhel*|*centos*) echo dnf; return ;;
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

PM=$(detect_pm)
if [ "$CHECK" = "1" ]; then
  say "package manager: $PM (check only, nothing installed)"
elif [ "$NO_PKGS" = "0" ]; then
  case "$PM" in
    pacman) REQ=(pciutils) ;;
    apt) REQ=(pciutils) ;;
    dnf) REQ=(pciutils) ;;
    zypper) REQ=(pciutils) ;;
    *) warn "unsupported distro - install manually: pciutils (GPU detect)"; REQ=() ;;
  esac
  if [ "${#REQ[@]}" -gt 0 ]; then
    say "installing: ${REQ[*]}"
    case "$PM" in
      pacman) sudo pacman -S --needed --noconfirm "${REQ[@]}" ;;
      apt) sudo apt-get update && sudo apt-get install -y "${REQ[@]}" ;;
      dnf) sudo dnf install -y "${REQ[@]}" ;;
      zypper) sudo zypper --non-interactive install "${REQ[@]}" ;;
    esac || warn "package install had errors - continuing (see README)"
  fi
else
  say "skipping packages (--no-packages)"
fi

copy_one() {
  local src="$1" dest="$2" rewrite="${3:-0}" tmp=""
  if [ "$CHECK" = "1" ]; then echo "COPY $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  # render first, compare second: $src still holds the Exec-path
  # placeholder, which never equals an installed file - comparing raw
  # would back up on every run. compare what we would write instead.
  tmp="$(mktemp)" || return 1
  if [ "$rewrite" = "1" ]; then
    # escape & (sed replacement metachar) in $HOME
    sed -e "s|@HOME@|${HOME//&/\\&}|g" "$src" > "$tmp"
  elif [ "$rewrite" = "2" ]; then
    # packaged /usr-style prefix: point the launcher at the real prefix
    sed -e "s|@HOME@/.local|${PREFIX}|g" "$src" > "$tmp"
  else
    cp -a "$src" "$tmp"
  fi
  if [ -e "$dest" ] && ! cmp -s "$tmp" "$dest"; then
    cp -a "$dest" "${dest}.bak-${BACKUP_TS}"
    say "backed up $dest"
  fi
  cat "$tmp" > "$dest"
  rm -f "$tmp"
  echo "installed $dest"
}

# Native Qt GUI: built when the toolchain is present, skipped cleanly when
# it is not. The menu entry launches this, never a terminal.
GUI_INSTALLED=0
build_gui() {
  local src="$PKGDIR/gui" builddir jobs
  [ -d "$src" ] || { warn "gui/ missing - GUI skipped"; return 0; }
  if [ "$NO_GUI" = "1" ]; then
    say "GUI skipped (--no-gui)"
    return 0
  fi
  if [ "$CHECK" = "1" ]; then
    GUI_INSTALLED=1
    echo "BUILD $BINDIR/maid-helper-gui (if cmake + Qt6 Widgets dev files are present)"
    return 0
  fi
  if ! command -v cmake >/dev/null 2>&1; then
    warn "GUI not built: cmake not found (terminal helper still installed)"
    return 0
  fi
  builddir=$(mktemp -d) || return 0
  jobs=$(nproc 2>/dev/null || echo 2)
  say "building the Qt6 GUI..."
  if cmake -S "$src" -B "$builddir" -DCMAKE_BUILD_TYPE=Release >/dev/null 2>&1 \
     && cmake --build "$builddir" -j"$jobs" >/dev/null 2>&1 \
     && [ -x "$builddir/maid-helper-gui" ]; then
    if install -m 0755 "$builddir/maid-helper-gui" "$BINDIR/maid-helper-gui"; then
      say "installed $BINDIR/maid-helper-gui"
      GUI_INSTALLED=1
    else
      warn "could not install maid-helper-gui"
    fi
  else
    warn "GUI not built: install cmake and Qt6 Widgets development files"
    warn "  openSUSE: qt6-base-devel | Arch: qt6-base | Fedora: qt6-qtbase-devel | Debian: qt6-base-dev"
  fi
  rm -rf "$builddir"
}

# shellcheck disable=SC1091
. "$PKGDIR/bin/kde-env.sh"
kde_env
say "$(kde_env_line)"

COPY_FAILED=0
for f in maid-helper maid-helper-run maid-helper-launch lib.sh mod-codecs.sh mod-gpu.sh mod-print.sh mod-fonts.sh mod-suite.sh mod-gamepad.sh mod-flatpak.sh mod-firmware.sh mod-kdeconnect.sh mod-bluetooth.sh kde-env.sh; do
  copy_one "$PKGDIR/bin/$f" "$BINDIR/$f" || COPY_FAILED=1
done
[ "$CHECK" = "0" ] && chmod +x "$BINDIR"/maid-helper "$BINDIR"/maid-helper-run "$BINDIR"/maid-helper-launch 2>/dev/null || true

build_gui

for f in "$PKGDIR"/desktop/*.desktop; do
  [ -f "$f" ] || continue
  # the menu entry needs the GUI; a terminal-only build skips it rather
  # than opening a terminal behind the user's back.
  if [ "$(basename "$f")" = "maid-helper.desktop" ] \
     && [ "$GUI_INSTALLED" != "1" ] && [ ! -x "$BINDIR/maid-helper-gui" ]; then
    [ "$CHECK" = "1" ] && echo "SKIP $SHAREDIR/applications/maid-helper.desktop (GUI not built)"
    continue
  fi
  copy_one "$f" "$SHAREDIR/applications/$(basename "$f")" $REWRITE
done
for f in "$PKGDIR"/desktop/*.svg; do
  [ -f "$f" ] || continue
  copy_one "$f" "$SHAREDIR/icons/hicolor/scalable/apps/$(basename "$f")" 0
done

# The version-specific source patch is gone; the automatic fix is
# mod-kdeconnect.sh (maid-helper --only kdeconnect --fix), not a rebuild.
# Older installs may still have the old patch artifact on disk.

if [ "$CHECK" = "1" ]; then say "(check only, nothing changed)"; exit 0; fi
# clean the old patch artifact left by earlier versions
rm -rf "$SHAREDIR"/maid-helper/patches
if [ "$COPY_FAILED" != "0" ]; then
  warn "some files failed to copy - install incomplete (see above)"
  exit 1
fi
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

say "done. Backups (if any): *.bak-${BACKUP_TS}"
say "start read-only: maid-helper --check   (then: maid-helper --fix)"
