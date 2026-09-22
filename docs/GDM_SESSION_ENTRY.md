# Opt-in Quattro GDM session entry

## Status

The S4 repository implementation is ready for temporary installation. It adds
an explicitly selectable **Quattro (Jetson preview)** Wayland session; it does
not make Quattro preferred, enable automatic login, enable the service at boot,
or alter GDM's configuration. No S4 file is installed yet.

Visible behavior remains unverified until the human physical gate. The local-VT
launcher remains the supported recovery path.

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
`session-N.scope` cgroup. It also requires the peer process environment to name
the exact `omarchy-quattro` Wayland desktop, preventing an ordinary Ubuntu
Wayland terminal from initiating the compositor. The same UID over SSH
therefore cannot manufacture a start request for another local session. Stop,
status, and collection retain
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
