# Workshop Baseline 0

## Observed on the current machine

Read-only inspection on 2026-09-16 reported:

| Item | Observed value |
|---|---|
| CPU architecture | `aarch64` |
| OS | Ubuntu 24.04.4 LTS (Noble) |
| Kernel | `6.8.12-1021-tegra` |
| CUDA compiler | `/usr/local/cuda/bin/nvcc` |
| Jetson monitor | `/usr/bin/tegrastats` |
| Kernel headers | `/usr/src/linux-headers-6.8.12-1021-tegra-ubuntu24.04_aarch64` |

The supplied baseline recorded Jetson Linux/L4T 38.2.1, 64 GB unified memory, Samsung 970 EVO 1 TB NVMe root storage, CUDA 13.2, cuDNN 9.20, and TensorRT 10.16. Read-only verification now shows that the installed system is L4T R39.2.1: `/etc/nv_tegra_release` reports `R39`, and the installed `nvidia-l4t-*` packages agree. The 38.2.1 value is therefore stale and should not be used for experiment-specific assumptions.

## Phase 1 preflight observations

- Session: X11 (`XDG_SESSION_TYPE=x11`), Ubuntu GNOME.
- Present: Weston 13, NVIDIA L4T Wayland, GBM, Weston, XWayland, PipeWire, and WirePlumber packages.
- Missing: `quickshell`, `hyprland`, `cmake`, `ninja`, `qmake6`, and `qdbus6` commands.
- No `/dev/dri`, `nvhost*`, or `nvidia*` device nodes were visible to the inspection process. `/dev` is presented through a restricted devtmpfs/tmpfs view, so this is an inspection-environment limitation until verified from the native desktop context; it is not evidence that the GPU is unavailable.

## Invariants

Do not replace or alter the Tegra kernel, UEFI/boot firmware, L4T, JetPack, NVIDIA userspace, CUDA, cuDNN, TensorRT, or NVMe boot configuration. No system package changes or installer execution belong in Phase 0.

## Evidence labels

“Observed” means read-only local inspection. “Source evidence” means inspection of upstream documentation/source. “Hypothesis” needs a controlled experiment. “Unknown” must not be silently converted into a plan assumption.
