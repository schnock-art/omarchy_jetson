# Hyprland and Jetson

## Known

The machine uses a Tegra kernel and NVIDIA Jetson userspace on Ubuntu 24.04. Hyprland is a Wayland compositor with a native ARM64 build path in principle, but ordinary NVIDIA desktop guidance cannot be assumed to apply to an integrated Jetson GPU.

## Hypothesis

If the current Jetson stack exposes the required Wayland/GBM/EGL interfaces, a source-built Hyprland session may work without changing the kernel or driver packages. The likely risk is compositor/backend integration, not CPU architecture.

## Unknown

- Whether the installed Jetson image exposes the exact GBM/EGL behavior expected by Hyprland’s current rendering backend.
- Whether a wlroots/aquamarine-class compositor can start on this L4T release.
- Whether external monitors, suspend, cursor rendering, screenshots, and hardware acceleration behave correctly.
- Whether a nested compositor test can provide meaningful evidence without becoming a system-session change.

## Safety boundary

No generic NVIDIA driver installation, DKMS module, kernel change, bootloader change, or display-manager replacement is acceptable. Any graphics experiment must be user-space, isolated, and reversible.
