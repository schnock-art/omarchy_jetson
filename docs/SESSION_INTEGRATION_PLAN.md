# Quattro session integration plan

## Goal

Move from the physically verified local-VT lab launcher to a normal, selectable
Quattro session at the GDM login screen while retaining GDM and Ubuntu as the
recovery environment.

This plan does **not** make Quattro start at boot, enable automatic login,
replace GDM, or silently make Quattro the preferred session. Those changes are
outside the repository's current safety contract and require a separate,
explicit design decision after the selectable-session gates pass.

## Current supported workflow

Today Quattro is a deliberately explicit lab session:

1. The operator logs into the normal GDM desktop once so the user's D-Bus and
   PipeWire runtime are available.
2. At a physical text console, the operator runs:

   ```sh
   cd /home/looco/repos/omarchy_jetson
   ./scripts/start-quattro-lab.sh
   ```

3. The launcher runs the syntax and host preflight before changing the display,
   stops GDM, waits for its graphical session to close, reclaims the same VT,
   and starts the Hyprland and Quickshell containers.
4. The user works in Quattro and may approve the bounded MVP agent in the
   Agents panel. Approval only prepares the detached adapter; Codex does not
   start until the session archive exists and GDM has returned.
5. `Super+Shift+E` exits Quattro. The launcher archives runtime state and logs,
   restores GDM, and leaves stopped labelled containers for recoverable log
   collection on the next launch.
6. The host-side adapter evaluates the completed archive. Human-only visual
   assertions are recorded explicitly; they are never inferred from logs.

The accepted end-to-end example is run `20260922-063507-9503`. It passed the
archived acceptance contract and returned to GDM. The run records base revision
`9e0533e3e9186586e5441c641617f31351aeecc8`; the MVP changes were uncommitted at
the time, so the committed handoff baseline is recorded separately in
`docs/MVP_MAINTENANCE.md`.

## Why a GDM entry is not only a desktop file

The current launcher owns operations that are inappropriate inside a GDM user
session: it elevates with `sudo`, stops the display manager that launched it,
manually switches VTs, and gives a container direct input, DRM, and TTY access.
A `.desktop` file which merely invokes that launcher would either fail without
an interactive password prompt or terminate its own parent display manager.

Session integration therefore requires a new lifecycle mechanism, not an
autostart shortcut. GDM/logind must own login and seat allocation; the Quattro
session must consume that assigned session without stopping GDM. Any necessary
privileged container setup must be exposed through a narrow, fixed host
service—never through a generic root command channel.

## Target architecture

The target keeps the existing four planes and changes only the display
lifecycle boundary:

```text
GDM login screen
    |
    | user explicitly selects "Quattro (Jetson preview)"
    v
unprivileged session wrapper in the logind seat/session
    |
    +--> fixed, versioned request to narrow host session service
    |       starts/stops only the reviewed Quattro containers
    |
    +--> sanitized runtime state and explicit action gateway
    |
    v
Hyprland + Quickshell
    |
    | normal logout or bounded failure
    v
GDM login screen; Ubuntu session remains available
```

The selectable entry must be named as a preview until all physical gates pass.
It must not modify GDM's default-session policy or rely on automatic login.

## Delivery stages

### S0 — Freeze the accepted lab baseline

Status: implemented and physically verified; commit handoff pending when this
plan was written.

- Commit the current MVP implementation and documentation to `main`.
- Record the exact container image IDs, upstream Omarchy revision, acceptance
  manifest hash, accepted run ID, and committed implementation revision.
- Prove the syntax and host fixture suites from the committed tree.

Gate: a clean checkout can run all non-display checks using the retained image
IDs, and the accepted archive still evaluates successfully offline.

### S1 — Separate lifecycle policy from the VT mechanism

Status: planned.

- Extract a session-neutral orchestration module for run IDs, evidence,
  collectors, action gateway startup, container labels, cleanup, and archival.
- Keep the existing local-VT launcher as a supported backend and recovery path.
- Define an explicit backend interface for `lab-vt` and future `gdm-session`
  modes; unknown modes fail closed.
- Add fixtures for startup failure, duplicate start, partial container start,
  logout, signal, timeout, archival failure, and idempotent cleanup.

Gate: the current physical VT workflow behaves identically, and its accepted
contract passes with the refactored shared orchestration.

### S2 — Prove logind/GDM seat ownership without installing a session

Status: planned investigation.

- Capture the environment and permissions GDM grants to a minimal test session:
  session type, seat, VT, DRM lease/master behavior, input access, D-Bus,
  PipeWire, runtime directory, and NVIDIA device access.
- Determine whether the compositor container can safely join that session or
  whether Hyprland must move to a host process with Quickshell remaining
  containerized.
- Record the decision and reject any design that requires stopping GDM,
  mounting a writable home into Quickshell, exposing Docker, or broadening the
  NVIDIA/host boundary.

Gate: a non-destructive probe establishes one viable architecture with exact
permissions and a documented recovery path. No production session entry is
installed yet.

### S3 — Implement a narrow session service and wrapper

Status: planned and conditional on S2.

- Add an unprivileged wrapper that validates its GDM/logind session and creates
  one run ID.
- If privileged setup remains necessary, add a root-owned service with fixed
  operations such as `start-session-v1`, `stop-session-v1`, and
  `collect-session-v1`. It must validate the caller, active seat, schema,
  run ID, and state transition; caller-supplied commands and arguments are
  forbidden.
- Bound startup and shutdown, stop the exact labelled resources only, archive
  evidence atomically, and always return control to GDM.
- Keep credentials and the coding agent in the host agent plane.

Gate: fixture tests cover normal, malformed, duplicate, unauthorized, timeout,
interruption, and recovery paths. A service security review confirms that it
cannot become a generic Docker or root execution API.

### S4 — Add an opt-in GDM session entry

Status: planned.

- Package the reviewed wrapper as `Quattro (Jetson preview)` under the normal
  Wayland session mechanism.
- Provide explicit install, verify, and uninstall commands. Installation must
  be idempotent and removal must restore the exact prior state.
- Do not change automatic login, the display manager, or GDM's configured
  default/preferred session.
- Keep the local-VT launcher documented as the recovery workflow.

Gate: from GDM, a human explicitly selects Quattro, observes the full visual
checklist, logs out normally, and sees GDM again. Ubuntu remains selectable and
works immediately afterward.

### S5 — Reliability and reboot acceptance

Status: planned.

- Test repeated Quattro login/logout cycles, failed container start, compositor
  crash, forced service timeout, power loss/reboot recovery, and an ordinary
  Ubuntu login after every failure class.
- Verify JetPack, CUDA/TensorRT, NVIDIA devices, audio, networking visibility,
  input, telemetry, agent state, and archived-run evaluation.
- Repeat on a clean reboot and retain one evidence bundle per scenario.

Gate: all automated contracts pass, all required human assertions are recorded,
GDM survives every tested path, and no stale container/session blocks the next
login.

### S6 — Decide whether “preferred” is safe

Status: explicitly deferred design decision.

After S5, the maintainer may decide whether “running by default” means only a
convenient selectable session or changing GDM's remembered/preferred session.
Automatic login, boot-time Quattro, or replacement of GDM remain prohibited by
the current contract. Any proposal to change that boundary must include an
independent recovery login, rollback procedure, physical failure testing, and
an explicit update to `AGENTS.md` approved by the maintainer.

## Definition of done

The integration is complete when Quattro can be explicitly selected at GDM,
normal logout and all bounded failure paths return to GDM, Ubuntu remains an
immediately usable alternative, the NVIDIA/JetPack stack is unchanged, and the
same archived acceptance contract passes. Until then,
`scripts/start-quattro-lab.sh` remains the only supported display launcher.
