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

Status: complete. The accepted source baseline is commit
`583d3280b36b9067b9d79036f347efffee74a92b`.

- Commit the current MVP implementation and documentation to `main`.
- Record the exact container image IDs, upstream Omarchy revision, acceptance
  manifest hash, accepted run ID, and committed implementation revision.
- Prove the syntax and host fixture suites from the committed tree.

Gate: a clean checkout can run all non-display checks using the retained image
IDs, and the accepted archive still evaluates successfully offline.

### S1 — Separate lifecycle policy from the VT mechanism

Status: physically verified. The shared lifecycle layer now owns
backend validation, run IDs, container labels, bounded readiness, atomic
session records, and evidence recovery. A separate session-services module owns
startup, readiness, archival, interruption, and idempotent cleanup for the
system-bus proxy, telemetry, agent-status collector, and action gateway. The
display launcher now retains only preflight, GDM/VT handoff, container display
mechanics, and restoration. `gdm-session` is reserved but rejected by that
launcher until S2 establishes its seat model.

Physical evidence: run `20260922-073620-56102` loaded the five required shell
milestones with no fatal marker, Hyprland exited with status `0`, the shell
ended with the expected Wayland shutdown signature, and GDM was active after
the human's normal exit. This confirms the refactored `lab-vt` lifecycle slice;
it is not a replacement for the earlier full MVP panel/input visual record.

- Extract a session-neutral orchestration module for run IDs, evidence,
  collectors, action gateway startup, container labels, cleanup, and archival.
- Keep the existing local-VT launcher as a supported backend and recovery path.
- Define an explicit backend interface for `lab-vt` and future `gdm-session`
  modes; unknown modes fail closed.
- Add fixtures for startup failure, duplicate start, partial container start,
  logout, signal, timeout, archival failure, and idempotent cleanup.

Gate: the current physical VT workflow behaves identically, and its accepted
contract passes with the refactored shared orchestration.

Final evidence: run `20260922-080145-91129` retained fresh telemetry and agent
snapshots, a correlated successful Codex refresh, and harmless workload
`sample-20260922-080228` with exit status `0`. All shell milestones passed,
Hyprland exited cleanly, the human confirmed the requested panels/actions, and
GDM was active after normal exit. The service fixtures cover duplicate
ownership, partial startup timeout, interrupted child cleanup, malformed
identity, atomic archival, and repeated cleanup. S1 is complete; S2 remains a
separate read-only investigation.

Source correlation: the first physical slice ran from a dirty tree based on
`72d459510df977c0ac43ac81c7eabb0a0cfefa50` and was committed as
`037ecdaaba26beeb4c426caaaac92ff16922e88a`. The final service-ownership run
records base `037ecdaaba26beeb4c426caaaac92ff16922e88a`; those tested working-tree
changes are committed as `8ffd128e485ac49440dea5c18a8efcafe960c81b`.

### S2 — Prove logind/GDM seat ownership without installing a session

Status: complete. The read-only probe is retained as
`artifacts/session-probes/20260922-083639.json`. It established the narrow
host-service architecture and identified GDM's explicit Wayland policy as the
only blocker. Reversible experiment `20260922-090045` then proved both Ubuntu
Wayland and Ubuntu Xorg sessions, preserved NVIDIA/CUDA operation, returned to
GDM, and restored the exact original configuration.
See [SESSION_INTEGRATION_DECISION.md](SESSION_INTEGRATION_DECISION.md).

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

The architecture, exact permissions, automated verification, human
observations, and mandatory rollback are documented. S2's acceptance gate is
met. See [GDM_WAYLAND_EXPERIMENT.md](GDM_WAYLAND_EXPERIMENT.md).

### S3 — Implement a narrow session service and wrapper

Status: implemented; temporary privileged installation health check passed.
S2 selected the containerized presentation plane with a narrow root-owned host
service. S3 now implements the versioned fixed-operation contract, peer/logind
authorization, atomic state machine, idempotency, recovery rules, unprivileged
client, and fixed container/evidence supervisor. The fixture and security gates
pass; see [GDM_SESSION_SERVICE.md](GDM_SESSION_SERVICE.md) and
[S3_SECURITY_REVIEW.md](S3_SECURITY_REVIEW.md). The S3 service is temporarily
installed, but this does not install a GDM
session entry. The five installed files match their
recorded hashes, the service is active but static (not boot-enabled), its
root-owned group socket is present, and an unauthorized root-peer request
failed closed without creating run state.

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

Gate result: passed for the repository implementation and temporary service
health/rollback boundary. Physical display behavior requires the opt-in S4 GDM
entry and remains unverified.

### S4 — Add an opt-in GDM session entry

Status: installed; first physical start failed closed before runtime launch.
The repository authorization fix passes fixtures but must be transactionally
refreshed before the physical gate is retried.
The wrapper now owns the complete start/status/stop/collect
lifecycle and start is bound to the GDM peer process's exact logind scope. The
hash-protected entry conductor is idempotent, preserves GDM/default settings,
refuses active-run removal, and requires the installed S3 bundle to be
transactionally refreshed first. See
[GDM_SESSION_ENTRY.md](GDM_SESSION_ENTRY.md). Both installed S4 files match
their install-time recorded hashes, and the static service/socket remained
healthy. The failure was traced to the confined service being unable to read
the GDM wrapper's `/proc/PID/environ`; the replacement validates the protected
AccountsService selection while retaining peer, logind, and exact-cgroup
checks. The follow-up retry reached the Quattro shell, but its first selection
exposed a wrapper response timeout and unhandled service broken pipe; the
second selection produced an `awaiting-visual-check` archive. The repository
now has a fixture-tested timeout/disconnect and canonical-evidence fix which
must be refreshed before the final physical acceptance retry. Physical
acceptance remains pending.

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
