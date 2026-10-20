# kdeconnectd early-login crash — kernel 7.2.11 / Plasma 6.8 fix

After the upgrade to kernel 7.2.11 and KDE Plasma 6.8.0 (Qt 6.11.2),
`kdeconnectd` dumped core on login:

```
kdeconnectd[15193]: could not connect to display
Could not load the Qt platform plugin "xcb" in "" even though it was found.
This application failed to start because no Qt platform plugin could be initialized.
```

## cause

`kdeconnectd` is D-Bus activated, and at login it can start before the
session environment (`XDG_SESSION_TYPE`, `WAYLAND_DISPLAY`) has been
propagated to the systemd user instance. `DISPLAY` is already set at that
point, so Qt's automatic platform detection picks `xcb` — but Xwayland is
not accepting connections yet. Qt treats a failed platform plugin as fatal
(`qFatal`), so the daemon aborts and leaves a core dump.

## the suite fix (no rebuild)

Maid Helper's `kdeconnect` doctor installs a small user-level wrapper and
points both activation paths (the D-Bus service and the XDG autostart
entry) at it:

```sh
maid-helper --only kdeconnect --fix
```

The wrapper probes `XDG_RUNTIME_DIR` for a `wayland-*` socket when
`WAYLAND_DISPLAY` is missing, then runs `kdeconnectd` with an ordered
`QT_QPA_PLATFORM` fallback (`wayland;xcb;offscreen` or
`xcb;wayland;offscreen`). It lives in `~/.local`, so KDE Connect package
updates never remove it. It takes effect at the next login.

## source patch

`0001-daemon-platform-fallback.patch` is the same fix as an upstream-style
git patch. It is shipped here as a reference/release artifact for distro
or upstream use:

```sh
cd kdeconnect-kde-26.08.2
git am /path/to/0001-daemon-platform-fallback.patch
# or: patch -p1 < 0001-daemon-platform-fallback.patch
cmake -B build -DBUILD_TESTING=OFF && cmake --build build
```

The old RPM-style duplicate (`kdeconnectd-platform-fallback.patch`) is no
longer shipped. The patch is attached to Maid Helper's GitHub releases
and installed to `~/.local/share/maid-helper/patches/kdeconnect-26.08.2/`
by `install.sh`.
