# Opt-in Quattro GDM session entry

## Status

The S4 session entry is installed and physically verified. Final run
`20260923-193649-29443` completed the archived acceptance contract, including
the bounded Codex archive review and explicit human visual assertions. S4 adds
an explicitly selectable **Quattro (Jetson preview)** Wayland session; it does
not make Quattro preferred, enable automatic login, enable the service at boot,
or alter GDM's configuration.

The GDM Wayland experiment `20260923-192434` is rolled back: its original GDM
file hash is restored, GDM is active, and Ubuntu on Xorg was verified after the
test. The local-VT launcher remains the supported recovery path.

The verified installation has matching hashes for both root-owned S4 files,
an active static S3 service and socket, and unchanged GDM and AccountsService
records at install time.
Fresh GDM experiment bundles record whether the entry is installed, its hash,
and whether it matches the repository source before the physical gate begins.

The 2026-09-22 attempt showed the entry in GDM, then returned to the greeter on
each of three starts. The service created no run. Journal evidence at
16:31:19, 16:31:30, and 16:31:36 recorded the wrapper being rejected because
the service could not read `/proc/PID/environ`. The unit deliberately lacks
`CAP_SYS_PTRACE`, so that authorization source was incompatible with the
installed confinement. The replacement keeps peer credentials, active logind
session checks, and exact cgroup membership, but validates GDM's selected
session using the bounded root-owned AccountsService record instead.

On 2026-09-23, the first retry reached a separate race: the root service spent
longer than the wrapper's 15-second response wait while startup was in flight;
the client disconnected and an unhandled broken pipe restarted the service.
The immediate second selection reached Quattro and produced archived shell,
telemetry, workload, action, and agent-status evidence, but it is still only
`awaiting-visual-check`. The follow-up fix gives the wrapper a 60-second
bounded response wait, treats a disconnected client as one failed delivery
rather than a service failure, and writes the evaluator's canonical log names
alongside the GDM-specific container evidence. It must be refreshed into the
installed S3 bundle before the final retry.

The final retry used that refreshed bundle and completed without a service
restart. Its archived evaluator found all required artifacts and milestones,
no configured fatal pattern, a completed harmless workload and Codex refresh,
and a completed MVP agent. The human confirmed rendering, panels, input,
audio, fixed actions, and `Super+Shift+E` return to GDM. The stored result is
passing; the historical failed attempts above remain retained as evidence.

## Lifecycle

GDM launches the installed unprivileged wrapper inside the selected local
Wayland/logind session. The wrapper creates one run ID and sends only fixed,
versioned operations:

```text
start-session-v1 -> status-session-v1 ... -> stop-session-v1 -> collect-session-v1
```

Natural compositor exit moves directly from status to collection. `SIGINT` or
`SIGTERM` sends the fixed stop operation before collection. Runtime failure is
collected and returned nonzero so GDM can close the failed session.

The service binds start authority to three facts simultaneously: Unix peer
credentials, the logind session owner, and the peer PID's exact
`session-N.scope` cgroup. It also requires the protected AccountsService record
to name `omarchy-quattro` as GDM's selected session, preventing an ordinary
Ubuntu Wayland terminal from initiating the compositor. This avoids depending
on `/proc/PID/environ`, which the installed service intentionally lacks
`CAP_SYS_PTRACE` permission to read. The same UID over SSH therefore cannot
manufacture a start request for another local session. Stop, status, and collection retain
the run/session ownership checks needed for bounded recovery.

## Installed files

The S4 conductor owns exactly:

- `/usr/libexec/omarchy-quattro/session-wrapper`; and
- `/usr/share/wayland-sessions/omarchy-quattro.desktop`.

The desktop entry has the exact display name `Quattro (Jetson preview)` and
executes only `session-wrapper run-session`. It accepts no prompt, command,
image, device, mount, environment, or Docker arguments.

## Transactional installation

S4 extends the installed service protocol, so refresh the verified S3 bundle
first. Refresh refuses changed installed files, stops the static service,
atomically replaces the reviewed bundle, starts it again, waits for its socket,
and restores the complete previous bundle if any step fails:

```sh
cd /home/looco/repos/omarchy_jetson
sudo ./scripts/quattro-gdm-session-install.py refresh --approve
```

Then inspect and install the entry:

```sh
./scripts/quattro-gdm-session-entry.py plan
sudo ./scripts/quattro-gdm-session-entry.py install --approve
sudo ./scripts/quattro-gdm-session-entry.py status
```

Installation is idempotent. It refuses pre-existing destination files, requires
the current reviewed S3 hashes and active socket, records GDM and AccountsService
hashes before writing, and verifies they did not change. It does not restart
GDM. With the currently restored `WaylandEnable=false` policy, the entry is not
yet a runnable physical test; do not infer display acceptance from installation.

## Rollback

The entry rollback is hash-protected and refuses while a run is active:

```sh
sudo ./scripts/quattro-gdm-session-entry.py uninstall --approve
```

It removes only the two recorded S4 files and its state record. It does not
alter GDM policy or remove the separately managed S3 service. The S3 service can
later be rolled back with its own conductor after the entry is removed.

## Physical gate

After installation, a separately approved test will temporarily reapply the
already-proven GDM Wayland candidate, restart GDM with SSH recovery available,
and explicitly select **Quattro (Jetson preview)**. The human must confirm:

- Hyprland and the full Quattro shell render on the assigned GDM VT;
- keyboard, pointer, audio, panels, telemetry, agent state, and fixed actions
  behave as in the accepted MVP;
- `Super+Shift+E` ends the session and returns to GDM;
- Ubuntu on Xorg remains selectable and works immediately afterward;
- the archived run passes automated evaluation plus explicit visual checks;
  and
- the original GDM policy is restored byte-for-byte after the test.

If the screen is blank or input is unavailable, use SSH to restore the GDM
Wayland experiment first. Preserve the run/service logs before changing code.
