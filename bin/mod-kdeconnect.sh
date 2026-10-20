#!/usr/bin/env bash
# Doctor: KDE Connect early-login crash and Android remote filesystem.
# D-Bus can activate kdeconnectd before the Wayland session environment
# reaches the systemd user manager; Qt then picks xcb while Xwayland is
# not ready and qFatal() aborts the daemon. The Android SFTP plugin also
# asks for "/", which Android 11+ refuses to list. Detect: kdeconnectd is
# installed but the user-level platform-fallback wrapper, activation
# overrides or sshfs storage-root shim are missing. Fix: install the
# wrapper and shim, point both activation paths at the wrapper. No root,
# no package rebuild, and it survives KDE Connect updates. Takes effect
# at the next login.
# Usage: mod-kdeconnect.sh check|fix. rc: 0 healthy/fixed, 2 needs attention.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090,SC1091
. "$here/lib.sh"
# shellcheck disable=SC1090,SC1091
. "$here/kde-env.sh"

MODE="${1:-check}"
WRAPPER="$HOME/.local/bin/kdeconnectd-wrapper"
DBUS="$HOME/.local/share/dbus-1/services/org.kde.kdeconnect.service"
AUTOSTART="$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop"
SSHFS_DIR="$HOME/.local/lib/maid-helper/kdeconnect-bin"
SSHFS_SHIM="$SSHFS_DIR/sshfs"
# MAID_KDECONNECTD overrides detection (the tests point it at a stub).
KDECONNECTD="${MAID_KDECONNECTD-$(command -v kdeconnectd 2>/dev/null || true)}"

[ -n "$KDECONNECTD" ] || { echo "skip - KDE Connect not installed"; exit 0; }

kde_env
kde_env_line

wrapper_ok() {
  [ -x "$WRAPPER" ] && grep -q 'QT_QPA_PLATFORM' "$WRAPPER" 2>/dev/null &&
    grep -q 'kdeconnect-bin' "$WRAPPER" 2>/dev/null
}
dbus_ok() {
  [ -f "$DBUS" ] && grep -Fqx "Exec=$WRAPPER" "$DBUS" 2>/dev/null
}
autostart_ok() {
  [ -f "$AUTOSTART" ] && grep -Fqx "Exec=$WRAPPER" "$AUTOSTART" 2>/dev/null
}
shim_ok() {
  [ -x "$SSHFS_SHIM" ] && grep -q 'storage/emulated/0' "$SSHFS_SHIM" 2>/dev/null
}

if wrapper_ok && dbus_ok && autostart_ok && shim_ok; then
  echo "ok - kdeconnectd starts through the wrapper; Android storage root is remapped"
  exit 0
fi

echo "NEEDS FIX - KDE Connect needs the platform-fallback / Android-storage wrapper"
[ "$MODE" = "fix" ] || exit 2

mkdir -p "$(dirname "$WRAPPER")" "$(dirname "$DBUS")" \
  "$(dirname "$AUTOSTART")" "$SSHFS_DIR" || exit 1

backup() {
  [ -e "$1" ] || return 0
  cp -a "$1" "$1.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
}

# write a generated file only when its content changes; back up the old one
write_file() {
  local dest="$1" tmp
  tmp="$(mktemp)" || return 1
  cat > "$tmp"
  if [ -e "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi
  backup "$dest"
  cat "$tmp" > "$dest" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

write_file "$SSHFS_SHIM" <<'SSHFS_EOF'
#!/bin/sh
# KDE Connect's Android SFTP plugin reports "/" as the remote path, but
# Android 11+ denies listing the filesystem root. Mount the primary
# shared storage instead; a path the phone already supplied (for example
# a user-selected folder) is left alone.
# Managed by Maid Helper (mod-kdeconnect.sh); edits are overwritten.

sshfs_bin=${MAID_SSHFS_REAL:-/usr/bin/sshfs}
if [ "$#" -gt 0 ]; then
    remote=$1
    shift
    case "$remote" in
        *:/) remote="${remote%/}/storage/emulated/0" ;;
        *:)  remote="${remote}/storage/emulated/0" ;;
    esac
    set -- "$remote" "$@"
fi
exec "$sshfs_bin" "$@"
SSHFS_EOF
chmod +x "$SSHFS_SHIM"

write_file "$WRAPPER" <<'WRAPPER_EOF'
#!/bin/sh
# Start kdeconnectd with a platform fallback list, even when D-Bus
# activates it before the Wayland session environment is ready.
# Managed by Maid Helper (mod-kdeconnect.sh); edits are overwritten.

# Put our sshfs shim first: KDE Connect asks Android for "/", which
# Android 11+ denies; the shim mounts /storage/emulated/0 instead.
if [ -d "$HOME/.local/lib/maid-helper/kdeconnect-bin" ]; then
    PATH="$HOME/.local/lib/maid-helper/kdeconnect-bin:$PATH"
    export PATH
fi

has_platform_arg=false
for arg in "$@"; do
    case "$arg" in
        -platform|--platform|-platform=*|--platform=*) has_platform_arg=true ;;
    esac
done

if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        [ -S "$socket" ] || continue
        WAYLAND_DISPLAY=${socket##*/}
        export WAYLAND_DISPLAY
        break
    done
fi

if [ -z "${QT_QPA_PLATFORM:-}" ] && [ "$has_platform_arg" = false ]; then
    prefer_xcb=false
    if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
        prefer_xcb=true
    elif [ "${XDG_SESSION_TYPE:-}" != "wayland" ] &&
         [ -z "${WAYLAND_DISPLAY:-}" ] && [ -n "${DISPLAY:-}" ]; then
        prefer_xcb=true
    fi
    if [ "$prefer_xcb" = true ]; then
        QT_QPA_PLATFORM="xcb;wayland;offscreen"
    else
        QT_QPA_PLATFORM="wayland;xcb;offscreen"
    fi
    export QT_QPA_PLATFORM
fi

exec /usr/bin/kdeconnectd "$@"
WRAPPER_EOF
chmod +x "$WRAPPER"

write_file "$DBUS" <<EOF
[D-BUS Service]
Name=org.kde.kdeconnect
Exec=$WRAPPER
EOF

write_file "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Exec=$WRAPPER
StartupNotify=false
X-KDE-autostart-phase=1
X-GNOME-Autostart-enabled=true
NoDisplay=true
Icon=kdeconnect
Name=KDE Connect
EOF

systemctl --user daemon-reload >/dev/null 2>&1 || true

if wrapper_ok && dbus_ok && autostart_ok && shim_ok; then
  echo "ok - wrapper installed; it takes effect at the next login"
  exit 0
fi
echo "FAILED - wrapper files are still incomplete"
exit 1
