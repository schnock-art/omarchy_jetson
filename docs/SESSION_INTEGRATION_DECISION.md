# GDM/logind session feasibility decision

## Decision status

The read-only S2 probe establishes a conditional architecture but identifies one
host-policy blocker: this Jetson has `WaylandEnable=false` in
`/etc/gdm3/custom.conf`.

Do not install a Quattro session entry or begin the privileged S3 service until
the maintainer explicitly chooses whether to run a reversible GDM Wayland
feasibility experiment. No GDM, login, device, NVIDIA, or session configuration
was changed during this investigation.

## Reproducing the probe

Run from a terminal inside the normal GDM desktop session:

```sh
cd /home/looco/repos/omarchy_jetson
probe="artifacts/session-probes/$(date +%Y%m%d-%H%M%S).json"
./scripts/quattro-session-probe.py capture --output "$probe"
```

Exit status `0` means the complete policy and capability gate is a candidate.
Exit status `1` means the JSON record is valid but contains a blocker. Exit
status `2` means the request or record is malformed. Re-evaluate a retained
record without touching the host:

```sh
./scripts/quattro-session-probe.py evaluate \
  --input artifacts/session-probes/PROBE.json
```

The probe is read-only. It calls fixed `loginctl`, `getfacl`, Git, and Docker
inspection commands, reads device metadata and GDM configuration, and writes
only its requested artifact using an atomic rename. It does not use `sudo`,
open devices, start a compositor, install a session, or change GDM.

## Observed Jetson result

Probe `artifacts/session-probes/20260922-083639.json` recorded the following:

| Capability | Observation |
| --- | --- |
| GDM/logind session | Active local user session `12`, `seat0`, `tty2`, VT 2, service `gdm-password` |
| Session type | X11 |
| User runtime | `/run/user/2002`, owned by `looco`, with D-Bus and PipeWire sockets |
| DRM primary nodes | 2 present; both readable and writable by the user |
| DRM render nodes | 2 present; both readable and writable by the user |
| NVIDIA device nodes | 4 character devices present; all readable and writable by the user |
| Raw input nodes | 15 present; none readable or writable by the user |
| Assigned session TTY | Readable and writable by the user |
| `/dev/tty0` | Not readable or writable by the user |
| Docker socket/API | Not accessible by the user |
| GDM Wayland policy | Disabled explicitly by `/etc/gdm3/custom.conf` |

The result is intentionally `blocked`, with `gdmWaylandEnabled` as the only
failed policy/capability check. The working tree was dirty during the probe and
its base revision was `4d97eb95a21cc0ad1a64b57f058ee2d4dcbfcfe2`.
The tested probe and decision implementation is committed as
`8ded5454355087b7e22cd3aeec48453fc9d8e15a`.

## Architecture selected if the blocker is resolved

The viable candidate remains **containerized Hyprland and Quickshell started by
a narrow root-owned host service**. The GDM session wrapper stays unprivileged
and supplies only its validated logind session identity and a generated run ID.

The service may:

- verify the caller owns the active local `user` session on `seat0`;
- derive the assigned VT from logind rather than accept an arbitrary device;
- start only the two reviewed images with fixed mounts, devices, capabilities,
  labels, and network policy;
- pass the assigned session TTY, `/dev/tty0`, DRM, input, and NVIDIA devices;
- stop only containers labelled with the validated run ID; and
- archive evidence and return control to GDM on normal exit or failure.

It may not accept commands, image names, device paths, Docker arguments, mount
paths, environment variables, or arbitrary prompts from the caller. It may not
expose Docker to the user/session, mount a writable host home, stop GDM, alter
automatic login, or change the preferred/default session.

A purely unprivileged container launcher is rejected: the user cannot access
Docker, raw input, or `/dev/tty0`. A host-native Hyprland installation is also
not selected because it would widen host package/runtime changes without
removing the GDM Wayland policy blocker.

## Required explicit decision

The safest current option is to keep the physically verified `lab-vt` launcher.
To continue toward a selectable GDM session, the maintainer must separately
authorize a **temporary, reversible GDM Wayland feasibility experiment**. That
experiment must be designed before execution and include:

1. an exact backup and checksum of `/etc/gdm3/custom.conf`;
2. an SSH recovery connection and tested command to restore the file and GDM;
3. no automatic login and no preferred/default-session change;
4. preservation of the existing Ubuntu Xorg session;
5. a reboot and normal Ubuntu login check before Quattro installation;
6. a minimal probe session before the real Quattro wrapper; and
7. immediate rollback if GDM, NVIDIA graphics, CUDA, or the normal desktop
   regresses.

Even after authorization, the first task is to write and review that experiment
and rollback tooling. It is not permission to install Quattro as the default or
to bypass the physical validation gates.
