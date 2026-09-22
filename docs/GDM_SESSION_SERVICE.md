# Narrow GDM session service

## Status

S3b is implemented and fixture-tested. The first slice implemented the
versioned control contract, peer authorization, logind validation, atomic state
transitions, idempotency, and unprivileged client. The second slice adds the
fixed container supervisor, bounded readiness/termination, exact label
ownership, service cleanup, atomic evidence archival, and post-archive removal
of only the two owned containers.

Nothing in this slice is installed under `/etc`, `/usr`, or GDM. The service is
not running on the host, GDM Wayland remains restored to its original disabled
policy, and `scripts/start-quattro-lab.sh` remains the only supported Quattro
display launcher.

## Boundary

The future root-owned service listens on the fixed Unix socket
`/run/omarchy-quattro/control.sock`. Unix peer credentials—not request data—
identify the caller. The service resolves the supplied session identifier with
fixed `loginctl show-session` calls and requires:

- a non-root peer matching the logind session owner;
- an active, local `user` session created by `gdm-password`;
- `seat0`, a consistent assigned `ttyN`/VT number, and Wayland type; and
- the same peer UID and session ID for every later operation on a run.

Each newline-delimited JSON request is limited to 16 KiB and must contain
exactly these fields:

```json
{
  "schemaVersion": 1,
  "requestId": "correlation-id",
  "operation": "start-session-v1",
  "runId": "20260922-120000-1234",
  "sessionId": "17"
}
```

The only accepted operations are `start-session-v1`, `stop-session-v1`, and
`collect-session-v1`. There is no command, argument, image, device, path,
environment, prompt, or Docker option field. Unknown versions, extra fields,
oversized records, malformed IDs, and unknown operations fail closed.

Every accepted request produces one correlated terminal result. Repeating an
identical request ID returns the stored result without invoking the runtime
again. A different request cannot start an already-owned run. State records
are mode `0600`, atomically replaced, and reject symlinks.

## State model

```text
new -> starting -> running -> stopping -> stopped -> collecting -> collected
          |                      |                         |
          +----------------------+-------------------------+--> failed
```

A stopped or collected run can be stopped again safely. A collected run can be
collected again safely. A failed start or stop remains recoverable through the
fixed stop/collect operations. Rejected malformed, duplicate, or unauthorized
requests do not change a healthy run's lifecycle state.

## Installation boundary

The service executes only `/usr/libexec/omarchy-quattro/session-runtime`. It
rejects a missing helper and rejects any helper that is not a regular,
root-owned executable with no group/world write bit. The supervisor applies the
same rule to its installed lifecycle modules. It never sources shell code from
the user-writable checkout. Host collectors, the action gateway, and workload
registry are launched from the checkout only after `setpriv` drops to the
validated desktop user.

The repository files are not installed yet, so the current host still fails
closed with `runtime-unavailable`. No group, socket, systemd unit, sudo rule, or
GDM entry exists. Temporary installation remains an explicit privileged gate.

`scripts/quattro-gdm-session-wrapper.py` is the unprivileged protocol client.
It derives the session ID from `XDG_SESSION_ID`, generates correlation IDs,
uses only the fixed socket, bounds the response, and rejects correlation
mismatches. It is not a GDM session entry.

## Fixed runtime

`scripts/quattro-gdm-session-runtime.sh`:

1. receives only the validated run/session identity selected by the service;
2. starts only `hyprland:phase2-runtime` and
   `quickshell:phase1-hypr-lab`, under fixed names and labels;
3. keeps network disabled and mounts Omarchy, runtime tests, the user bus, and
   PipeWire through the existing reviewed boundaries;
4. passes only the assigned session TTY plus fixed tty0, DRM, input, and NVIDIA
   access to the compositor;
5. supervises the existing collectors and action gateway;
6. stops only containers whose exact run label matches;
7. atomically archives service state, logs, inspection data, workload state,
   acceptance contract, revision, and terminal session state; and
8. removes the owned stopped containers and runtime volume only after the
   archive succeeds.

Normal, malformed, duplicate, unauthorized replay, timeout, interruption,
failed-start recovery, idempotent cleanup, fixed-helper, archive, and unsafe
identifier fixtures pass. The focused review is recorded in
[S3_SECURITY_REVIEW.md](S3_SECURITY_REVIEW.md). The next gate is a reviewed,
temporary root-owned installation followed by a controlled physical session;
it must not add the S4 GDM entry or change GDM policy yet.

## Temporary installation checkpoint

The maintainer approved the temporary S3 service installation. Inspect the
exact files and hashes without privilege:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-gdm-session-install.py plan
```

Install and manually start the service with:

```sh
sudo ./scripts/quattro-gdm-session-install.py install --approve
```

The conductor creates the dedicated `omarchy-quattro` group, adds `looco` only
when necessary, atomically installs five reviewed files, reloads systemd, and
starts the service. It explicitly verifies that the unit is **not enabled** at
boot. It does not edit or restart GDM. Do not rerun the earlier GDM Wayland
experiment for this checkpoint.

Read-only installed status:

```sh
sudo ./scripts/quattro-gdm-session-install.py status
```

Expected status is `filesMatch: true`, `serviceActive: true`,
`unitFileState: static`, `enabledAtBoot: false`, and `socketPresent: true`.
Systemd reports an install-less unit as `static`; this means it has no boot
target links and is not enabled. A new login is required
before the desktop user's newly added supplementary group is effective, but no
logout is needed merely to verify root-side service health.

Rollback is explicit and hash-protected:

```sh
sudo ./scripts/quattro-gdm-session-install.py uninstall --approve
```

Uninstall refuses to delete any installed file whose hash changed. On a normal
rollback it stops the service, removes only the recorded files, reverses only
the group membership/group created by this installation, reloads systemd, and
retains repository evidence. Installation failure runs the same bounded
rollback automatically.
