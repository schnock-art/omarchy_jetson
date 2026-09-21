# Narrow GDM session service

## Status

S3 implementation is in progress. The first slice implements and fixture-tests
the versioned control contract, peer authorization, logind validation, atomic
state transitions, idempotency, and unprivileged client. The runtime adapter is
deliberately fail-closed until the fixed container startup and evidence paths
are extracted from the accepted lab launcher and reviewed as the second slice.

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

## Current fail-closed behavior

`scripts/quattro-gdm-session-service.py` currently uses a fail-closed runtime
adapter. Even if it were started manually, `start-session-v1` cannot launch a
container and returns `runtime-unavailable`. This is intentional: enabling a
root service before its Docker argument list, child ownership, timeouts,
cleanup, and archival are reviewed would cross the project's authority
boundary.

`scripts/quattro-gdm-session-wrapper.py` is the unprivileged protocol client.
It derives the session ID from `XDG_SESSION_ID`, generates correlation IDs,
uses only the fixed socket, bounds the response, and rejects correlation
mismatches. It is not a GDM session entry.

## Next S3 slice

The next slice will extract a fixed GDM-session runtime adapter that:

1. derives the assigned VT and device set only from the validated identity;
2. starts only the reviewed Hyprland and Quickshell images and fixed mounts;
3. owns bounded child/container shutdown and interruption recovery;
4. archives into the existing per-run evidence contract atomically; and
5. exposes no caller-selected executable, argument, path, image, device, or
   environment value.

Only after its normal, malformed, duplicate, unauthorized, timeout,
interruption, and recovery fixtures pass can S3 undergo its security review.
S4 installation remains frozen until then.
