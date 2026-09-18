# Omarchy Quattro on Jetson AGX Orin

Phase 0 reconnaissance for adapting the Omarchy Quattro desktop/agent experience to an NVIDIA Jetson AGX Orin Developer Kit.

This repository is research and planning only. It must not install packages, modify boot or kernel configuration, replace NVIDIA components, or run an Omarchy installer.

## Current position

The preferred direction is a user-space Ubuntu adaptation: preserve Ubuntu/L4T/JetPack/CUDA/TensorRT and investigate Quattro’s reusable shell and agent interfaces independently. A full Arch replacement is not justified by current evidence.

The largest uncertainty is not ARM64 itself; it is whether a usable Hyprland/Wayland session can run on the Jetson Tegra graphics stack without disturbing the working desktop.

## Documents

- [Baseline](docs/BASELINE.md)
- [Quattro architecture](docs/QUATTRO_ARCHITECTURE.md)
- [Compatibility matrix](docs/COMPATIBILITY_MATRIX.md)
- [Package mapping](docs/PACKAGE_MAPPING.md)
- [Hyprland on Jetson](docs/HYPRLAND_JETSON.md)
- [Quickshell](docs/QUICKSHELL.md)
- [Agent integration](docs/AGENT_INTEGRATION.md)
- [Porting options](docs/PORTING_OPTIONS.md)
- [Risks](docs/RISKS.md)
- [Phase 1 plan](docs/PHASE_1_PLAN.md)
- [Quattro lab startup](docs/STARTUP_WORKFLOW.md)

## Status

Phase 1 preflight is recorded in [docs/PHASE_1_RESULTS.md](docs/PHASE_1_RESULTS.md). The isolated build is prepared but currently blocked by Docker access from the managed session; no host changes were made.
