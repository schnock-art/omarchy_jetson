# Risks

## Critical

- Running an Omarchy or Arch installer.
- Installing generic NVIDIA drivers, DKMS modules, kernels, or boot components.
- Replacing L4T/JetPack packages or the display/session stack globally.
- Modifying NVMe partitions, boot configuration, or firmware.

## Significant

- Installing a compositor or display manager system-wide before a nested/session-isolated test.
- Letting package resolution pull Arch or desktop-NVIDIA dependencies into Ubuntu.
- Running unreviewed third-party Quickshell plugins; they execute unsandboxed in the shell process.
- Assuming a successful ARM64 compile implies Jetson graphics compatibility.

## Control principle

Prefer source inspection, user-local builds, containers, nested windows, temporary configs, and explicit logs. Every experiment must have a clear stop condition and leave Baseline 0 intact.
