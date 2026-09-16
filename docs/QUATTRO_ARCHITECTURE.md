# Quattro architecture

Quattro replaces the older collection of desktop processes with one long-running `omarchy-shell` Quickshell instance. Hyprland autostart launches it; the shell hosts the bar, panels, menus, overlays, notifications, OSD, lock/polkit surfaces, and services as plugins.

The shell has a QML entry point, plugin and bar-widget registries, first-party plugins, a user plugin directory, and a persisted `~/.config/omarchy/shell.json`. Shell IPC exposes operations such as ping, summon, toggle, rescan, reload, and plugin listing. Third-party plugins are git checkouts and run unsandboxed inside the shell.

This architecture is attractive for the Workshop because participant indicators, GPU telemetry, model status, and notifications could eventually be ordinary plugins. It also means the shell is not a standalone “theme”: it depends on a compositor, Wayland surfaces, session startup, fonts/icons, utilities, and a working IPC path.

The strongest reusable boundary appears to be the shell/plugin model and IPC contract. The weakest boundary is the surrounding Omarchy command/configuration and Arch packaging layer.
