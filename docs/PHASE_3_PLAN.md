# Phase 3 — Reliable Jetson Quattro lab

## Objective

Turn the proven Quattro-on-Hyprland session into a repeatable lab environment
that is quick to start, easy to diagnose remotely, and does not replace the
Jetson's normal GDM desktop. This phase builds on the working bar, network,
Bluetooth power control, PWR panel, audio access, and live telemetry panel.

```text
physical TTY: start or visually confirm a lab run
SSH:          observe, diagnose, collect evidence, and recover
normal GDM:   remains the default everyday desktop
```

## Low-interference rule

Most work is agent-owned and can be prepared, verified, and reviewed without
touching the physical display. The user is needed only when an active local VT
is essential to prove visible rendering, input, or reboot recovery.

| Work item | Owner | User involvement |
| --- | --- | --- |
| Scripts, log parsing, documentation, container checks | Aster | None |
| SSH diagnostics during a run | Aster | None after SSH is connected |
| Physical Quattro launch | User | Run one command on text TTY |
| Visual confirmation after a material UI change | User | Brief look/click and report |
| Reboot resilience check | User | Reboot once and confirm SSH returns |

No task in this phase may silently install a display manager, change the
default login session, modify Jetson power mode, alter network configuration,
or enable an autostart service.

## Batch A — One-command evidence and health report

### Goal

Add `scripts/quattro-health-report.sh`, safe to run over SSH before, during,
or after a lab run. It should summarize rather than dump logs.

### Automated checks

- launcher/image/config prerequisites;
- state and exit code of the exact Hyprland and Quickshell containers;
- whether the newest archived run has both container logs and inspect data;
- full-shell milestones: configuration loaded, Hyprland IPC connected,
  PipeWire connected, notification server registered;
- Jetson-specific milestones: telemetry collector sample, PWR panel loaded,
  network backend, Bluetooth backend;
- expected shutdown signature, distinguished from an early shell failure;
- unexpected `ERROR` or plugin-load failures with nearby context.

### Acceptance

The script returns zero only when the requested state is healthy, prints a
short PASS/WARN/FAIL summary, and includes exact log/archive paths for follow
up. It must not start or stop containers, change GDM, or modify host settings.

### User gate

None. Aster implements and tests it against retained runs.

## Batch B — Repeatable lifecycle checks

### Goal

Prove that the launcher can archive a completed run, preflight the next run,
and preserve a useful evidence trail every time.

### Automated checks

- run `./scripts/start-quattro-lab.sh --check` from an eligible local TTY when
  available, without stopping GDM;
- validate fresh runtime state after an archived run;
- test the health report against a completed run and against no active run;
- document recovery commands for the two expected failure windows: before and
  after Hyprland owns the display.

### User gate

At most one physical launch after Batch A: run the existing
`./scripts/start-quattro-lab.sh`, confirm the bar, then exit with
`Super+Shift+E`. All log review is remote.

## Batch C — Reboot resilience

### Goal

Verify that the lab remains reproducible after an ordinary Jetson reboot
without making Quattro a login-session replacement.

### Procedure

1. Aster records pre-reboot baseline: Git revision, Docker image presence,
   host runtime prerequisites, and health-report output.
2. User performs one ordinary reboot at a convenient time.
3. User confirms SSH returns; Aster performs read-only post-reboot checks.
4. User performs one normal physical lab launch and exits cleanly.
5. Aster compares the new health report with the baseline and records it.

### Acceptance

GDM returns normally after reboot, Docker and images are available, the same
launcher works, Quattro renders the bar, and no persistent system setting was
added to achieve it.

### User gate

One reboot and one physical launch. Everything else is automated.

## Deferred required workstream — Agent integration

Agent integration is intentionally deferred from the current physical baseline
while the compositor and hardware shell are stabilized, but it is a required
lab capability, not optional polish. It is tracked here so the missing agents
icon is an explicit known gap rather than an accidental omission.

The next agent batch should inventory the upstream agent UI and commands,
separate portable provider/IPC behavior from Arch-specific package helpers,
and add the smallest useful ARM64-compatible bridge. It must preserve the
lab's current isolation boundaries and must not enable autonomous background
agents without a separate decision.

Its acceptance gate will be a visible agents widget plus a safe read-only
status/usage path, followed by one controlled launch test. Provider launching,
approvals, skills, monitoring, and local CUDA/TensorRT inference remain
separate sub-batches rather than being bundled into the first icon port.

## Batch D — Optional polish after stability

Only begin these once B and C are green. Each is an isolated batch with the
same physical-test gate.

1. **Telemetry history:** a small read-only in-memory graph of CPU/GPU,
   temperature, RAM, and input power.
2. **Connectivity detail:** actual Wi-Fi/Ethernet identity and a concise
   failure reason, retaining the current narrow D-Bus boundary.
3. **Bluetooth clarity:** adapter state and connected-device count; retain the
   existing explicit power toggle as the only control.
4. **Jetson power detail:** explain available `nvpmodel` modes read-only; do
   not expose mode-changing controls by default.

## Explicitly out of scope

- replacing GDM or making Hyprland/Quattro the default desktop;
- automatic Quattro start at login or boot;
- generic NVIDIA drivers, kernel, firmware, or JetPack changes;
- audio policy work unless a lab workload needs it;
- broad host D-Bus, network, or privileged-container access;
- installing the full Arch/Omarchy system on the Jetson.

## Completion criteria

Phase 3 is complete when B and C have passed, the health report explains a
failed or completed run remotely, and the repeatable workflow is documented in
`STARTUP_WORKFLOW.md` and `LAB_VISIBILITY.md`.
