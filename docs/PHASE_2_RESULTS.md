# Phase 2 — Hyprland layer-shell investigation

Date: 2026-09-17

## Current result

The host has no Hyprland package installed, and Ubuntu does not currently provide a suitable native package through the enabled repositories. The official Hyprland guidance recommends a source build for Ubuntu because packaged versions may be outdated.

An isolated ARM64 Ubuntu 26.04 source configuration reached the Hyprland dependency checks with GNU 15.2 and OpenGL detected. The current source requires a matching Hypr ecosystem stack, including `hyprwayland-scanner`, `hyprutils`, `hyprlang`, `hyprcursor`, `hyprgraphics`, and `aquamarine`; these are not supplied by the Jetson host.

The matching libraries now build successfully: hyprwayland-scanner, hyprutils, hyprlang, hyprcursor, hyprgraphics, and aquamarine. Hyprland itself reaches its final dependency check. The current Wayland protocol release is 1.49, but it requires Wayland scanner 1.25 while Ubuntu 26.04 supplies 1.24; therefore the next isolated step is to build the matching Wayland core/scanner and protocol releases together. No native Hyprland installation or session changes have been made.

With the matching Wayland 1.26 development build and Hypr ecosystem libraries, current Hyprland 0.56.0 configured successfully on ARM64 with XWayland disabled. Compilation then stopped in `MiscFunctions.cpp` because the Ubuntu 26.04 GCC/libstdc++ combination does not expose `std::ranges::starts_with` used by this current source. The next test should pin a compatible Hyprland release/commit or use a compiler/standard-library combination known to implement that API; no upstream source patch has been applied.

Hyprland v0.54.2 was then tested. It configured successfully with XWayland disabled, but compilation failed in ranges/view code when paired with current Hypr utility libraries and GCC 15. A tag check also shows that v0.53.3, v0.54.0, v0.54.2, and v0.55.4 all request C++26, so moving to Ubuntu 24.04/GCC 13 would not address the language/library issue.

## Toolchain reconnaissance

The current upstream installation guidance explicitly calls for C++26 support and lists Clang 19 or newer as a supported compiler. The libc++ feature-status documentation lists `__cpp_lib_ranges_starts_ends_with` as implemented, and an ARM64 probe in the disposable Ubuntu 26.04 container confirmed that Clang 19 with libc++ compiles and runs `std::ranges::starts_with` successfully.

The supported compiler and library pair is available for ARM64 in that container (`clang-19`, `libc++-19-dev`, and `libc++abi-19-dev`). This makes a fully matched Clang/libc++ rebuild the preferred next experiment, rather than patching Hyprland sources or mixing different C++ standard libraries.

For a release-pinned experiment, Hyprland v0.54.2's lockfile specifies these matching source revisions:

| Component | Revision |
| --- | --- |
| aquamarine | `5d2cb726b16ee349df443f84b64cff53221b6983` |
| hyprcursor | `b62396457b9cfe2ebf24fe05404b09d2a40f8ed7` |
| hyprgraphics | `7d63c04b4a2dd5e59ef943b4b143f46e713df804` |
| hyprland-protocols | `1cb6db5fd6bb8aee419f4457402fa18293ace917` |
| hyprlang | `7615ee388de18239a4ab1400946f3d0e498a8186` |
| hyprutils | `e63f3a79334dec49f8eb1691f66f18115df04085` |
| hyprwayland-scanner | `0a692d4a645165eebd65f109146b8861e3a925e7` |

Every C++ Hypr component must be rebuilt using the same Clang/libc++ settings. Otherwise, an apparent compile fix can turn into an ABI/runtime failure.

## Successful pinned libc++ build

Hyprland v0.54.2 and its release-pinned Hypr dependencies were rebuilt in a separate `/opt/hypr-clang` prefix inside the disposable Ubuntu 26.04 ARM64 container. The build uses Clang 19 with libc++ and has XWayland disabled.

The build also required libc++-compatible versions of the otherwise system-provided C++ dependencies: RE2 (with Abseil) and muparser. The final executable was deliberately linked to the isolated copies of those libraries while retaining the container's normal graphics, DRM, GBM, input, and Wayland libraries. This avoids mixing libstdc++ and libc++ C++ ABIs.

The complete artifact installed successfully and a non-graphical startup check reports:

```
Hyprland 0.54.2
commit 59f9f2688ac508a0584d1462151195a6c4992f99
no xwayland
```

`ldd` confirms that Aquamarine, all Hypr libraries, RE2, Abseil, and muparser resolve from `/opt/hypr-clang/lib`; the executable also starts with a valid `XDG_RUNTIME_DIR`. This proves the C++ toolchain and dependency route on Jetson ARM64. It does **not** yet prove a DRM/NVIDIA compositor session: the artifact remains container-only until the next controlled runtime experiment.

## Host finding

Real DRM Weston already initializes NVIDIA EGL 1.5 and OpenGL ES 3.2 on the Orin. The next compositor test should therefore use a retained, fully built Hyprland image and run it only after the user stops the current Weston session. GNOME/GDM remains recoverable through SSH.

## Controlled container runtime result

A fresh, network-isolated runtime container was started from the retained image with the NVIDIA container runtime and `/dev/dri` exposed. Hyprland began normal initialization, enumerated the Jetson DRM cards, and then stopped while creating its Aquamarine backend.

The retained log identifies the precise boundary: the container has no active physical seat or virtual terminal. Its embedded `seatd` cannot open `tty0`, and `libseat` reports that the client is not active when it tries to open `/dev/dri/card1` and `/dev/dri/card2`. Aquamarine consequently skips both cards as unavailable KMS devices and cannot create `CBackend`.

This is not an NVIDIA EGL, GBM, or Hyprland build failure; graphics initialization has not yet been reached. No host display, Wayland socket, or desktop service was mounted into the test container, and the host session was not changed.

The next meaningful runtime test must run on the Jetson's active local VT/seat, coordinated with stopping the currently active compositor or display manager. That step can affect the visible desktop and should be performed with SSH already connected as the recovery path.

## First real DRM session: successful rendering, missing input metadata

The local-VT test subsequently started the NVIDIA DRM backend successfully. Aquamarine selected `/dev/dri/card2` (`nvidia-drm`), detected the connected DP-1 monitor and its preferred 2560×1440 mode, created a GBM allocator, and initialized an OpenGL ES 3.2 renderer reporting `NVIDIA Tegra Orin (nvgpu)/integrated`. This is the first real Hyprland graphics-session proof on the Jetson.

The initial container had no `/run/udev` and therefore no host udev database. Although `/dev/input/event0` through `event14` were visible, `hyprctl devices` reported no keyboards, mice, tablets, touch devices, or switches. This is expected: libinput requires udev's `ID_INPUT` and `ID_INPUT_*` properties to classify event nodes. It is not an Aquamarine or NVIDIA rendering failure.

`containers/hyprland-runtime/` now defines a derived `hyprland:phase2-runtime` image. Its entrypoint starts `seatd` only long enough to claim the active VT, transfers the seat socket to an unprivileged `hyprland` user, then drops privileges before executing Hyprland. The root-bypass flag is therefore not used by the derived image.

`scripts/run-hyprland-drm.sh` is the corresponding host-side launcher. It intentionally uses only the required DRM, input, VT, NVIDIA, and read-only `/run/udev` bindings. It adds `c 13:* rwm` so USB input devices connected after container creation can be opened; the `/dev/input` mapping already covers event devices existing at start. The next run will validate enumeration and hot-plug with this image/launcher pair.

The launcher determines the active text VT at runtime rather than assuming a fixed F-key mapping. On this host `Ctrl+Alt+F1` is GDM's graphical login; use a spare text console such as `Ctrl+Alt+F3`, log in there, stop GDM, and then run the launcher from that same console.

To avoid an interactive gap on systems where stopping GDM blanks or changes the active VT, invoke the launcher with `--stop-gdm`. It stops GDM and immediately continues into the container from the already active text-console process.
