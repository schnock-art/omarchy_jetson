# Quattro architecture

Quattro replaces the older collection of desktop processes with one long-running `omarchy-shell` Quickshell instance. Hyprland autostart launches it; the shell hosts the bar, panels, menus, overlays, notifications, OSD, lock/polkit surfaces, and services as plugins.

The shell has a QML entry point, plugin and bar-widget registries, first-party plugins, a user plugin directory, and a persisted `~/.config/omarchy/shell.json`. Shell IPC exposes operations such as ping, summon, toggle, rescan, reload, and plugin listing. Third-party plugins are git checkouts and run unsandboxed inside the shell.

This architecture is attractive for the Workshop because participant indicators, GPU telemetry, model status, and notifications could eventually be ordinary plugins. It also means the shell is not a standalone “theme”: it depends on a compositor, Wayland surfaces, session startup, fonts/icons, utilities, and a working IPC path.

The strongest reusable boundary appears to be the shell/plugin model and IPC contract. The weakest boundary is the surrounding Omarchy command/configuration and Arch packaging layer.

## Session integration boundary

The accepted `lab-vt` backend separates session-neutral lifecycle policy,
fixed host-service ownership, and physical display mechanics. A future GDM
backend must reuse the first two and replace only the VT/GDM mechanism.

The S2 capability probe selects a conditional architecture: an unprivileged
GDM wrapper identifies its active logind session while a narrow root-owned
service starts the two fixed containers with the assigned seat devices. The
wrapper does not receive Docker access, and the service does not accept caller
commands, image names, paths, mounts, or device arguments.

The reversible GDM experiment passed and restored the original host policy, so
the S3 service may now be implemented and fixture-tested. Its versioned
fixed-operation contract, peer authorization, and state machine are documented
in [GDM_SESSION_SERVICE.md](GDM_SESSION_SERVICE.md). Do not install the service
or a GDM session entry until the fixed runtime adapter and S3 security gate
pass. The physical `lab-vt` backend remains the recovery path.
