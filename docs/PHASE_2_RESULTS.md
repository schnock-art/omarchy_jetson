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

Ubuntu may configure `sudo` with `use_pty`, causing `tty` inside a sudo command to report `/dev/pts/N` even when the user invoked it from a real VT. The launcher uses `SUDO_TTY` when supplied, preserving the original `/dev/ttyN` for device passthrough.

## Revised console handoff and verification

The launcher now captures the console before invoking sudo itself, and accepts
an explicit `--tty /dev/ttyN` override. `--check` validates the runtime image,
Docker daemon, console device, and required device/database paths without
stopping GDM or switching consoles. A real launch verifies the selected VT is
foreground, stops GDM if requested, and explicitly switches back to the selected
VT before starting seatd. It restores GDM on normal exit, failure, or handled
termination signals when it stopped an active GDM service. SIGKILL, power loss,
or a host hang cannot be recovered by a shell trap; retain SSH access.

From the local text console, run without an outer sudo:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/run-hyprland-drm.sh --check
./scripts/run-hyprland-drm.sh --stop-gdm
```

If automatic console detection fails, check `tty` and supply that exact path:

```sh
sudo ./scripts/run-hyprland-drm.sh --check --tty /dev/tty3
sudo ./scripts/run-hyprland-drm.sh --stop-gdm --tty /dev/tty3
```

Verification: shell syntax and diff checks pass; explicit tty3 preflight passes
on the host. The full runtime entrypoint successfully runs `Hyprland --version`
without the root-bypass flag. A physical display/input test of this revised
handoff still requires the local console. No display service was stopped during
these checks.

Correction to earlier descriptions: seatd remains privileged throughout the
session to broker device access; only the compositor drops privileges. Also,
the input cgroup wildcard alone does not prove hot-plug support: newly created
device nodes and udev notifications must also reach the container. The current
`--device=/dev/input` mapping should be tested with keyboard/mouse plugged in
before launch; hot-plug remains unverified.

## Splash followed by seat deactivation (17:09 local time)

The revised launcher reached visible Hyprland output. The container log confirms
seatd accepted UID/GID 2002, NVIDIA EGL/GLES initialized, and libinput enumerated
the MOSART and Telink keyboards/mice. Thus initial input enumeration is fixed.
At elapsed 6.196 seconds seatd began disabling the client, then input devices
were removed. Host logs show the preceding GNOME/Xorg session was still exiting
between 17:09:30 and 17:09:34, after Hyprland started at 17:09:27. A late VT
switch during teardown is the leading hypothesis; the logs do not identify the
initiator of that switch. Page-flip-pending errors also appeared during startup
and may require investigation if the black screen persists with an active seat.

The container ended with status 137, OOMKilled=false, following SSH recovery;
this does not establish an earlier compositor crash. It is retained as
`hyprland-phase2-drm-20260917-1709` for inspection.

The launcher now snapshots live graphical session scopes on seat0 and waits up
to 60 seconds for those scopes to finish after stopping GDM, before switching
back to the selected VT and launching Hyprland. A timeout aborts and restores
GDM. A minimal smoke configuration enables full logs and provides Super+Shift+E
to exit; the preferred display mode is unchanged to isolate the handoff change.
Shell syntax, host preflight, and Hyprland's own `--verify-config` check pass.
The revised physical-session test remains pending.

## Confirmed interactive Hyprland session and next panel test

The user subsequently confirmed that the mouse works and Super+Shift+E returns
to the normal desktop. Docker records exit status 0 at 17:15:10 local time.
The successful container is preserved as `hyprland-phase2-drm-working-20260917`.
This establishes working physical input and a clean compositor exit after the
graphical-session teardown fix.

The launcher now accepts `--panel`. It starts the existing `quickshell:phase1`
image as UID 2002 with NVIDIA rendering access, and shares a fresh Docker volume
containing only this test's Wayland runtime directory with Hyprland. Quickshell
waits up to 60 seconds for the compositor socket. The host's desktop runtime
directory is not shared. Both containers are stopped on exit; their logs and
the explicitly named runtime volume are retained for diagnostics.

Run from the local text console:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/run-hyprland-drm.sh --check --panel
./scripts/run-hyprland-drm.sh --stop-gdm --panel
```

Expected result: a dark 56-pixel bar across the top, labelled
`Jetson + Hyprland + Quickshell`, with a counter that increments when clicked.
Super+Shift+E exits as before. The QML uses PanelWindow with a top exclusive zone
and namespace `jetson-layer-smoke`, following the
[Quickshell 0.3.1 PanelWindow API](https://quickshell.org/docs/v0.3.1/types/Quickshell/PanelWindow/).

While running, inspection from SSH:

```sh
sudo docker logs quickshell-layer-smoke
sudo docker exec --user 2002:2002 \
  -e XDG_RUNTIME_DIR=/tmp/hypr-runtime \
  -e LD_LIBRARY_PATH=/opt/hypr-clang/lib \
  hyprland-phase2-drm /opt/hypr-clang/bin/hyprctl layers
```

The namespace appearing in `hyprctl layers`, visible anchored output, and click
counter/log messages are the acceptance checks. A QML loaded message alone does
not establish that the layer surface is mapped. Shell checks pass; an offscreen
QML attempt correctly lacks a PanelWindow backend, so full panel validation is
pending the physical run. This is a protocol/input smoke test, not Quattro yet.

## Layer panel success and first Quattro-derived component

The user confirmed the top bar was visible and clicks incremented its counter.
Quickshell logs record `JETSON_LAYER_PANEL_LOADED` followed by click counts 1
through 8. Hyprland exited with status 0. EGL probing warnings remain in the
client log despite successful visible rendering; a Wayland-disconnected warning
at compositor exit is expected. The successful containers are preserved as
`hyprland-layer-success-20260917` and `quickshell-layer-success-20260917`.

The next panel revision adds an adapted clock on the right using upstream
Quattro's unmodified `Model.js` at Omarchy commit
`2fbac0c8e88eca704af1650ce721a494bd11a3d0`. Source provenance and license live in
`tests/runtime-smoke/quattro-clock/`. This isolates upstream date/format logic
without loading its full theme, calendar, settings, and command dependencies.
Right-click cycles formats in memory; the initial format includes seconds.
The client uses the host timezone via a read-only `/etc/localtime` mount.

The actual ClockFace QML loaded successfully under Qt's offscreen backend,
produced a nonempty label, cycled formats, and passed an ISO week-year boundary
check (`2021-01-01` is week 53). This checks the clock adapter, not layer-shell
rendering. The upstream model copy was verified byte-for-byte. The next visual
check uses the same `--stop-gdm --panel` command; verify seconds tick and
right-click changes the clock format before exiting with Super+Shift+E.

## Full-shell compatibility harness

Manual component-by-component testing is no longer the default approach. The
runtime launcher now supports `--quattro`, which runs Omarchy's real
`shell/shell.qml` in a disposable sibling Quickshell container. The Omarchy
checkout is mounted read-only at `/omarchy`; the shell receives a fresh runtime
directory and an empty temporary home, so no host Omarchy configuration or
plugin state is changed. One physical run can therefore report all first-load
errors, then subsequent runs validate groups of dependencies rather than a
single widget at a time.

The first headless compatibility pass reaches `shell.qml` and its Bar import.
It stops at `module "Quickshell.Hyprland" is not installed`. The retained
Quickshell 0.3.1 build was explicitly configured with `HYPRLAND=OFF`; Omarchy's
bar imports that module. Upstream Quickshell documents no extra dependency for
the module beyond Wayland, so an isolated rebuild is in progress with the
original feature profile and only `HYPRLAND=ON` changed. This is a build-feature
gap, not a QML source-porting issue.

After the feature-enabled image is verified, `--quattro` will use it and the
next full-shell run replaces the component loop. The physical test remains one
manual session because only the active local VT can validate DRM, input, and
layer surfaces; failures and import/service discovery are automated in the
container logs.

The isolated rebuild completed successfully and was snapshot as
`quickshell:phase1-hypr`. It preserves the original Quickshell feature profile
but enables `HYPRLAND=ON`. The image contains `Quickshell.Hyprland`; the full
shell's offscreen load now progresses through every QML import and stops only
when Bar.qml attempts to create a PanelWindow, which is expected without a
Wayland/layer-shell compositor. The `--quattro` launcher selects this image and
discovers Hyprland's instance signature from the shared runtime volume before
starting the full shell. The next physical test is therefore ready.

The first physical `--quattro` invocation started Hyprland successfully but did not launch the Quickshell sidecar: the launcher passed its host filesystem path to `sh` inside the container. The sidecar exited with status 2 and reported the missing host path. This was corrected to use the existing `/test/...` container mount path. No Quattro code ran in that attempt; the next invocation is the first full-shell runtime test.
