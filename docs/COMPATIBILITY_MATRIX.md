# Compatibility matrix (initial)

| Component | Rating | Assessment / likely action |
|---|---|---|
| Quickshell/QML shell | LIGHT GREEN | ARM64 is plausible; build and Qt module availability must be tested in user space. |
| Qt/QML | LIGHT GREEN | Ubuntu Noble supplies Qt, but exact Quickshell Qt version/modules need mapping. |
| Wayland client surfaces | GREEN | Ubuntu/Jetson already has a graphical stack, but session details must be verified. |
| Hyprland compositor | ORANGE | ARM64/source build is plausible; Tegra GBM/EGL and wlroots-class behavior are unproven. |
| Quattro shell plugins | YELLOW | QML is portable in principle, but shell commands, paths, portals, and compositor IPC assume Omarchy. |
| Shell IPC | LIGHT GREEN | Quickshell IPC is conceptually portable if the shell launches successfully. |
| Themes/fonts/icons | GREEN | Mostly data files; package and path conversion required. |
| Notifications/panels/OSD | YELLOW | Implemented in-shell, but depend on D-Bus, PipeWire, UPower, NetworkManager, and session services. |
| Omarchy CLI | ORANGE | Many commands encode pacman/Arch paths and system assumptions; selectively port only useful commands. |
| Arch package repository | RED | Must not be introduced as a replacement for Ubuntu/JetPack; no distro migration in Phase 0. |
| Generic NVIDIA DKMS/desktop driver path | RED | Must be excluded; it risks the Tegra stack. |
| Agent abstraction | LIGHT GREEN | Process/provider integration is likely reusable after removing Arch-specific launch helpers. |
| x86_64 prebuilt tools | RED/YELLOW | Audit individually; build ARM64 equivalents or omit. |
| Jetson CUDA/TensorRT | GREEN | Preserve as an independent Workshop capability, not as a Quattro prerequisite. |
