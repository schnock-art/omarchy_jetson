# Network, Bluetooth and power visibility — 2026-09-18

The user confirmed the audio panel/control test succeeded. The next batch
uses `quickshell:phase1-hypr-lab`, derived from the tested audio image, with
Python GIO bindings for read-only compatibility helpers.

## Integration

`system-bus-readonly.sh` runs xdg-dbus-proxy as the host desktop user for the
duration of the launcher. Only its filtered socket enters the container.
Allowed services: NetworkManager, BlueZ, UPower and both power-profile names.
Allowed methods are property reads, object enumeration, introspection and
selected NetworkManager queries. Property writes, pairing, connection changes,
power-profile changes, login-manager power actions and secrets queries are not
allowed by this proxy. The existing session-bus and audio access are unchanged.
The proxy exits during launcher cleanup; its temporary directory/log is retained.

The network-status helper reads the host NetworkManager's primary connection
through GIO rather than inspecting the container's isolated network namespace.
It supplies Quattro's tab-separated status and detail formats. Transfer rates,
ping, band selection and VPN-specific presentation remain unsupported.

The image's busctl produced an invalid-header error against the host proxy.
A narrow adapter handles Quattro's `--json=short get-property` calls using GIO;
all other forms fail explicitly. No upstream Omarchy files were modified.

## Verified remotely

- Real Quickshell networking, Bluetooth and UPower modules initialized offscreen:
  four network devices, Bluetooth adapter `localhost.localdomain`, mains power.
- Helper read the active Wi-Fi interface, strength, frequency, IPv4 and gateway.
- Desktop power-profile read returned `balanced`.
- Host `nvpmodel -q` separately returned `MODE_30W`, mode ID 2. These are distinct
  concepts; the generic desktop profile is not a Jetson power budget indicator.
- A property-write probe targeting a nonexistent property was denied by the
  proxy with AccessDenied. No operational setting was changed.
- Complete `--quattro --check --tty /dev/tty3` passed audio, session-bus and
  system-service checks, without stopping GDM. The proxy was cleaned up on exit.

Build: `sudo docker build -t quickshell:phase1-hypr-lab containers/quickshell-lab`.

## Remaining physical check

Run `./scripts/run-hyprland-drm.sh --stop-gdm --quattro` from the physical TTY.
Open network, Bluetooth and power panels. Check the displayed Wi-Fi/IP,
Bluetooth adapter/known devices, and power profile. This is a visibility batch:
buttons may still appear but write operations are blocked. Do not interpret
unavailable battery percentage on a mains-powered Jetson as a failure.
Exit with Super+Shift+E and confirm normal desktop recovery.

Pairing, switching networks, suspend/reboot, NVIDIA power-mode controls and
Jetson telemetry in the panel require subsequent work. No such action was run.

## Follow-up: Bluetooth toggle and Jetson power panel

The user confirmed network visibility. The unresponsive Bluetooth toggle also
called an absent `omarchy-bluetooth-power` helper. A container-local replacement
now uses GIO to write BlueZ Adapter1.Powered for the single detected adapter.
The proxy permits BlueZ Properties.Set (not limited to Powered by the proxy;
the helper limits its own operation to Powered). Network and power-profile
writes remain blocked. Bluetooth pairing/discovery methods remain blocked.
This is session-only power control, not upstream rfkill persistence. A hard or
soft radio block may prevent powering on and is not overridden by this helper.

The helper was tested through the filtered socket: off, confirmed off, on,
confirmed on, restored original on state. No connected Bluetooth devices were
listed before the test. Physical button operation still requires confirmation.

Upstream power UI gates opening on battery presence. The disposable runtime
copy now substitutes a Jetson panel with a text PWR button and NVIDIA mode
queried by `nvpmodel -q` at session start. This is explicitly a snapshot of the
configured mode, not current wattage or live telemetry. It enables no mode
changes. Qt's QML formatter parsed the panel successfully; full visual loading
remains unverified. A headless Weston attempt failed due to a host backend
library symbol error, before connecting Quickshell. No host library was changed.

## Icon-font and power-entry-point correction

The user confirmed Bluetooth button operation, but reported square glyphs and
no PWR button. The image had only DejaVu Sans Mono for the generic monospace
family, with no Nerd Font. The lab image now includes JetBrainsMono Nerd Font
Regular from Nerd Fonts v3.4.0, pinned by SHA256 in the Dockerfile. Source:
https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.4.0
The runtime fontconfig prefers this family for monospace. A test as UID 2002
with HOME=/tmp verified family selection and glyph coverage for Bluetooth
U+F0293 and Wi-Fi U+F092F. The separate Omarchy logo font still resolves.

The launcher also now starts `/tmp/omarchy-runtime/shell/shell.qml`, rather
than the original checkout entry point, keeping relative QML imports within
the compatibility copy. The power panel emits JETSON_POWER_PANEL_LOADED on
creation to distinguish a loading problem from a visual one. Physical rendering
of the corrected icons and power panel remains to be checked.

## Physical result — 2026-09-18

The lab runtime was tested on the Jetson display. Network information appeared;
Bluetooth power toggled successfully; Nerd Font glyphs rendered after the font
image update; and the corrected Jetson power icon appeared and opened its panel.
This confirms the visible lab-status batch end to end. The power panel showed
the NVIDIA mode read at startup. No network change, pairing, profile change,
suspend, reboot, or NVIDIA mode change was performed.

## Phase 3 stability result — 2026-09-19

The Quattro lab completed its reboot-resilience check without changing the
normal GDM session. A pre-reboot baseline captured GDM, Docker, the desktop
user's D-Bus and PipeWire sockets, kernel version, and both retained lab
images. After a normal reboot, the read-only verification matched that
baseline. A subsequent physical Quattro run rendered successfully and exited
cleanly back to GDM.

The post-run health report recorded 15 passes, no warnings, and no failures.
It confirmed configuration load, Hyprland IPC, PipeWire, notifications, Jetson
power panel, clean Hyprland exit, and a mounted live Codex usage record (114
prompts on the day of the test). The exact run evidence is retained under
`artifacts/quattro-runs/20260919-204854/`; the corresponding health report is
under `artifacts/quattro-health/20260919-205151-health.txt`.

## Phase 4 visibility result — 2026-09-19

The first three broader lab-visibility capabilities were confirmed together on
the Jetson display: the Codex activity panel, the short in-memory CPU/GPU
telemetry history graph, and the read-only workload registry. The user saw the
telemetry graph render and the completed harmless sample job in the workload
panel.

The retained health report recorded 15 passes, no warnings, and no failures.
It verified the mounted Codex record (145 prompts on the test day) and the
completed `Harmless sample` workload. The run evidence is retained under
`artifacts/quattro-runs/20260919-211800/`; the health report is
`artifacts/quattro-health/20260919-212104-health.txt`.

These panels remain observational: the workload registry has no arbitrary
command, stop, or control surface, and telemetry history is session-local.
Deliberate agent actions remain a separately scoped Phase 4 decision.
