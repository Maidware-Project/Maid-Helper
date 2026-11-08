# third-party and credits

Maid Helper is Maidware work under the **GPL-3.0-or-later** license in `LICENSE`. It does not bundle third-party software; it checks and (with explicit consent where required) invokes tools provided by your system.

## Called at runtime, not bundled
Provided by your system/distribution (modules vary):
- **bash** and core userland.
- **bluetoothctl** (BlueZ, GPL): Bluetooth checks (module: bluetooth).
- **pactl** (PulseAudio tools, GPL) and **PipeWire/WirePlumber** integration (system components; Helper may write user WirePlumber config snippets as part of its fixes) — audio/Bluetooth quality checks.
- **flatpak** (LGPL-2.1+): remotes/apps checks (module: flatpak).
- **fwupd / fwupdmgr** (LGPL-2.1+): firmware update capability checks (module: firmware).
- **KDE Connect** (`kdeconnectd`/CLI, GPL): checks/fixes via a user wrapper/shim approach (module: kdeconnect); Qt/KDE frameworks are system components.
- **CUPS/printing**, **codec stacks** (GStreamer/FFmpeg packages), **GPU/driver tooling**, **gamepad**, **fonts** helpers — invoked via distro packages as appropriate; patent-encumbered codecs and non-free items follow the module’s consent/safety rules (non-free drivers never installed by this tool; fonts like Microsoft core fonts only with explicit consent).
- **kdialog / zenity / notify-send** (optional): user-facing dialogs/notifications.
- **D-Bus / systemd (user)**: used where applicable by modules/wrappers.

## Optional build/runtime (GUI, not bundled here)
- **Qt 6 / C++ toolchain** (CMake, Qt Widgets) if you build the optional native GUI (`gui/`); Qt is licensed under its applicable terms (LGPL/commercial).

## Referenced, not bundled
- **freedesktop.org / XDG** specifications for desktop integration.

Everything else in this repository is original Maidware work. Corrections welcome.
