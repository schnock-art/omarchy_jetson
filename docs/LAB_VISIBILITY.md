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
