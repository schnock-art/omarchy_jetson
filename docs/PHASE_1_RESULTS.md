# Phase 1 preflight results

Date: 2026-09-16

## Completed

- Confirmed the active session is Ubuntu GNOME on X11.
- Confirmed Weston 13 is installed.
- Confirmed Jetson Wayland, GBM, EGL, Weston, XWayland, PipeWire, and WirePlumber packages are installed.
- Confirmed Quickshell, Hyprland, CMake, Ninja, and Qt build tools are not installed on the host.
- Resolved the baseline version discrepancy: the machine reports L4T R39.2.1 in `/etc/nv_tegra_release`.

## Blocked

The disposable Docker build could not start because this managed session cannot access `/var/run/docker.sock`. The socket is owned by `nobody:nogroup`, the Docker daemon is not reachable through systemd here, and the session’s `sudo` path is disabled by security policy.

## Native Jetson Docker build result

With `sudo docker`, the ARM64 Ubuntu 24.04 container successfully:

- pulled the `ubuntu:24.04` ARM64 image;
- installed the compiler, CMake, Ninja, Qt, Wayland, GBM, and related development dependencies;
- cloned the current Quickshell source;
- detected the GNU 13.3 C/C++ toolchain and ARM64 architecture;
- detected Wayland, OpenGL, Vulkan headers, and the enabled Quickshell Wayland features.

Configuration then failed because Ubuntu Noble’s Qt 6.4.2 packages reference private Qt include directories that are not present, including `QtQuick/6.4.2` and `QtWaylandClient/6.4.2`. The current Quickshell build guidance requires at least Qt 6.6, so Ubuntu 24.04’s stock Qt version is below the documented minimum as well.

This is a real Ubuntu userspace/Qt-version blocker, not an ARM64 compiler failure and not yet a Jetson GPU failure. The test container `quickshell-phase1` was removed afterward.

No host packages, permissions, drivers, kernel settings, or desktop configuration were changed.

## Next action

The Qt-version/private-header issue was isolated with an Ubuntu 26.04 ARM64 container. With Qt 6.10.2 plus `qt6-base-private-dev`, `qt6-declarative-private-dev`, and `qt6-wayland-private-dev`, CMake configuration completed. Adding Ubuntu's `libcli11-dev` package then allowed the Quickshell C++ build to complete successfully. The retained artifact reports `Quickshell 0.3.1`, revision `c6a516096dd84d5255b409482eb4bf740b952f88`, and responds to `--help`.

This establishes that current Quickshell source can compile for ARM64 when supplied with a sufficiently new Qt and its private headers. It does not yet establish runtime compatibility on Jetson's L4T R39.2.1 userspace, nor does it validate the NVIDIA GBM/EGL path. The retained build container is `quickshell-phase1-artifact`; it can be removed after the runtime experiment.

## Controlled Wayland runtime smoke test

Started a detached Weston 13 headless compositor on a temporary per-user Wayland socket and launched the retained ARM64 Quickshell binary from a container with that socket mounted read/write. The minimal QML configuration reached `WORKSHOP_WAYLAND_SMOKE_OK`, proving that Quickshell can connect to a Wayland compositor and initialize its QML shell.

The first nested test used Weston’s Pixman renderer. A follow-up test used the real DRM Weston session on `/dev/dri/card2` with NVIDIA EGL/GL and launched the containerized Quickshell with the NVIDIA runtime and `/dev/dri` exposed. It reached `WORKSHOP_WAYLAND_SMOKE_OK` without the earlier Mesa/Zink errors. The remaining `egl: failed to create dri2 screen` warnings come from the container’s EGL probing; Weston itself had already confirmed the native NVIDIA EGL path. The temporary Quickshell runtime container was removed; the build image remains available as `quickshell:phase1`.

A visible normal Wayland window also loaded successfully from `tests/runtime-smoke/panel.qml`. A `PanelWindow` variant was rejected because this Weston desktop shell does not advertise the layer-shell protocol; the next integration phase must use a layer-shell-capable compositor or temporarily use normal windows for UI work.

Do not add the user to a Docker group or change device permissions solely for this experiment without reviewing the security and baseline implications.
