# Quattro lab startup workflow

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

For an SSH-safe summary of the current or most recently archived run, use:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-health-report.sh
```

Add `--require-run` when a completed or active run is required and a missing
run should be treated as a failure. The report is read-only: it does not start
or stop containers, change GDM, or modify host settings. The broader low-touch
roadmap is recorded in [PHASE_3_PLAN.md](PHASE_3_PLAN.md).

Each report is also saved automatically under
`artifacts/quattro-health/` with a timestamped filename. Historical run logs
under `artifacts/quattro-runs/` are intentionally retained as evidence; they
are not deleted by the report script.
