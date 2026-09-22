# Quattro lab startup workflow

## Current supported lifecycle

From the Jetson's physical text console, start the lab session with:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/check-syntax.sh
./scripts/start-quattro-lab.sh
```

The launcher requires the local TTY because it hands the active VT to
Hyprland. It keeps the host's normal desktop as the default login session.
The script archives logs and inspection data from the two exact stopped
containers used by a completed prior lab run, then removes those stopped
containers so a new one can start. Archives are local under
`artifacts/quattro-runs/` and are ignored by Git.

The launcher generates one run ID and explicitly carries it through `sudo`.
It also selects the fixed `lab-vt` lifecycle backend. Backend names, run IDs,
container labels, bounded readiness waits, cleanup, and evidence recovery share
the session-neutral policy in `scripts/quattro-session-common.sh`. Fixed
host-service startup and ownership live in `scripts/quattro-session-services.sh`.
Unknown backends fail before the launcher can change the display.
Both lab containers are labelled with that ID, so recovery on the next launch
returns stopped-container logs to the original bundle rather than creating a
second timestamped archive. Agent state, runtime snapshots, and display logs
for one attempt must therefore share one directory. Recovery writes new
temporary files and atomically renames them, so a root-owned file left by an
older cleanup cannot block the next launch. Completed bundles are normalized
back to the desktop user's ownership.

Use SSH for observation and non-display actions while Quattro is running:

```sh
ssh looco@192.168.1.172
sudo docker logs -f quickshell-quattro-smoke
```

Exit the session with `Super+Shift+E`. The launcher stops the experiment and
restores GDM. If startup fails before the compositor takes control, the shell
preflights abort before GDM is stopped where possible. A diagnostics-only run
is available from the physical TTY:

```sh
./scripts/start-quattro-lab.sh --check
```

This workflow deliberately does not autostart Quattro at login, create a GDM
session entry, change NVIDIA power settings, or alter network configuration.
It is the supported operational baseline while the staged
[session integration plan](SESSION_INTEGRATION_PLAN.md) is implemented.

The important lifecycle boundary is that this launcher starts from a physical
text console, stops GDM only after all preflight checks pass, owns the selected
VT until Hyprland exits, archives evidence, and starts GDM again. Do not put
this command in GDM autostart or a Wayland session desktop file: a proper GDM
session must instead use logind's assigned seat and avoid stopping its parent
display manager.

For an SSH-safe summary of the current or most recently archived run, use:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-health-report.sh
```

Add `--require-run` when a completed or active run is required and a missing
run should be treated as a failure. The report is read-only: it does not start
or stop containers, change GDM, or modify host settings. The broader low-touch
roadmap is recorded in [PHASE_3_PLAN.md](PHASE_3_PLAN.md).

The report separates evidence sources so an archived verdict does not depend on
temporary live-session mounts:

```sh
./scripts/quattro-health-report.sh --host       # host readiness only
./scripts/quattro-health-report.sh --live       # active containers only
./scripts/quattro-health-report.sh --latest     # newest retained archive
./scripts/quattro-health-report.sh --run RUN_ID # one retained archive
```

The deterministic MVP conductor uses the same versioned contract as the
archived evaluator:

```sh
./scripts/quattro-mvp.py preflight
./scripts/quattro-mvp.py status --run-id RUN_ID
./scripts/quattro-mvp.py evaluate --run-id RUN_ID
# Add --write-result only when intentionally recording the evaluation artifact.
./scripts/quattro-mvp.py record-visual --run-id RUN_ID --passed true \
  --reason 'Human observed the bundled visual checklist.'
./scripts/quattro-mvp.py resolve-visual-gate --run-id RUN_ID
./scripts/quattro-mvp.py evaluate --run-id RUN_ID --write-result
./scripts/quattro-mvp.py complete-run --run-id RUN_ID
```

The host-side agent adapter is deliberately explicit and repository-scoped.
The normal flow is to approve it in the Agents panel, wait for the panel to say
`waiting`, then exit Quattro normally. The detached adapter starts Codex only
after the run bundle is complete and GDM has returned. Observe it over SSH:

```sh
RUN_ID=the-run-id-shown-in-artifacts/quattro-runs
watch -n 2 "jq . artifacts/quattro-runs/$RUN_ID/agent-run.json"
```

To stop that exact bounded adapter:

```sh
./scripts/quattro-agent-adapter.sh --run-id "$RUN_ID" --stop
```

For an already completed archive, an operator can also launch it directly with
`--approve` and no `--wait-for-session`. It can inspect evidence and perform
safe repository work, but it pauses for physical or visual checks. It does not
stop GDM or launch a display session.

Each report is also saved automatically under
`artifacts/quattro-health/` with a timestamped filename. Historical run logs
under `artifacts/quattro-runs/` are intentionally retained as evidence; they
are not deleted by the report script.

## Recovery quick reference

From SSH, first restore the normal desktop if it is not active:

```sh
sudo systemctl start gdm3
systemctl is-active gdm3
```

Inspect exact retained lab containers before removing anything:

```sh
sudo docker ps -a --filter name=hyprland-phase2-drm \
  --filter name=quickshell-quattro-smoke
sudo docker inspect hyprland-phase2-drm
sudo docker inspect quickshell-quattro-smoke
```

The next local-VT launcher invocation archives and removes stopped labelled
containers. Do not manually delete them before that evidence is retained. Stop
a still-running MVP adapter independently with its exact run ID:

```sh
./scripts/quattro-agent-adapter.sh --run-id RUN_ID --stop
```

## Reboot-resilience check

Before a planned normal reboot, capture a read-only baseline over SSH:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-reboot-check.sh --capture
```

After SSH returns and the normal GDM desktop is available, verify the exact
baseline path printed by the capture command:

```sh
./scripts/quattro-reboot-check.sh --verify artifacts/reboot-baselines/<timestamp>.json
```

The check verifies GDM, Docker, the desktop user's D-Bus and PipeWire sockets,
the kernel, and the two retained lab images. It changes no system state.

## Read-only GDM session capability probe

From the normal GDM desktop, capture the current logind seat, runtime sockets,
device permissions, Docker boundary, and GDM Wayland policy without changing
the host:

```sh
probe="artifacts/session-probes/$(date +%Y%m%d-%H%M%S).json"
./scripts/quattro-session-probe.py capture --output "$probe"
```

A valid probe may exit `1` when it records a policy blocker. See
[SESSION_INTEGRATION_DECISION.md](SESSION_INTEGRATION_DECISION.md) before
interpreting or acting on the result.

## Temporary S3 service checkpoint

The S3 control service can be installed for a non-display health and rollback
check without changing GDM or enabling anything at boot:

```sh
./scripts/quattro-gdm-session-install.py plan
sudo ./scripts/quattro-gdm-session-install.py install --approve
sudo ./scripts/quattro-gdm-session-install.py status
```

Do not rerun the GDM Wayland experiment and do not invoke the session start
operation at this checkpoint. Visible compositor acceptance requires the later
opt-in S4 GDM entry. Roll back the temporary service with:

```sh
sudo ./scripts/quattro-gdm-session-install.py uninstall --approve
```

See [GDM_SESSION_SERVICE.md](GDM_SESSION_SERVICE.md) for expected status and
hash-protected rollback behavior.
