# Proposed Phase 1

The smallest useful experiment is a user-space Quickshell feasibility test, before Hyprland or Omarchy integration. Before that, resolve the L4T version discrepancy and establish whether the inspection shell has visibility of the Jetson graphics device nodes.

1. Record the current graphical session and relevant Qt/Wayland environment read-only.
2. Reconcile the supplied L4T 38.2.1 baseline with the installed 39.2.1 package versions.
3. Obtain the Quickshell source and inspect its supported build configuration.
4. Build it in a temporary user-owned directory without installing packages system-wide, using only already-present toolchains or an explicitly approved isolated build environment.
5. Run a trivial QML/Quickshell surface in the existing session or an isolated nested environment.
6. Capture compile errors, missing Qt modules, renderer errors, and clean shutdown behavior.

Success reduces the Qt/ARM64 uncertainty. Failure still produces an actionable dependency or graphics report. Only after review should the next experiment test a minimal compositor/session path. The full Quattro shell, agent controls, autonomous behavior, and Jetson inference services are out of scope for this phase.
