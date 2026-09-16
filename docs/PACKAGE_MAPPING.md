# Package mapping (initial)

Quattro’s release model is Arch/pacman-oriented. The upstream package metadata can publish `aarch64` artifacts, but that does not make the package directly installable on Ubuntu. The first adaptation should therefore be source/config extraction plus a small Ubuntu-native dependency manifest, not an Arch package installation.

| Quattro area | Ubuntu ARM64 direction | Action |
|---|---|---|
| Quickshell | Build from source or use a verified ARM64 package if available | User-space build experiment |
| Qt6/QML modules | Ubuntu Noble Qt6 packages, exact module names to verify | Map after Quickshell build requirements are known |
| Hyprland | Source build or isolated prebuilt ARM64 route | Do not install system-wide until graphics path is understood |
| Wayland/session tools | Existing Ubuntu packages and current session | Inspect only; preserve current desktop |
| PipeWire/WirePlumber | Existing Ubuntu/Jetson session services | Reuse if present; do not replace |
| D-Bus/portals/polkit | Ubuntu equivalents | Adapt service names and permissions |
| Fonts/icons/themes | Copy or package as user data | Low risk, reversible |
| `omarchy-*` commands | Shell scripts requiring audit | Port selectively; omit package/boot/driver commands |
| Arch/AUR dependencies | No direct Ubuntu assumption | Replace, build, or omit individually |
| NVIDIA packages | JetPack/L4T packages already in baseline | Never substitute generic desktop NVIDIA packages |

The full mapping remains an open Phase 0 work item because the exact current manifests and install scripts need a complete source inventory.
