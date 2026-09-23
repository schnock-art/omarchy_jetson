# Omarchy Quattro on Jetson AGX Orin

A reversible Ubuntu/JetPack adaptation of the Omarchy Quattro desktop and
agent experience for an NVIDIA Jetson AGX Orin Developer Kit.

The project has progressed from reconnaissance to an accepted physical MVP.
Run `20260922-063507-9503` passed the full archived acceptance contract:
Hyprland and the real Quattro shell rendered on the Jetson, required panels and
input were observed by the human operator, normal exit restored GDM, the
detached Codex agent completed the non-visual checks, and the offline evaluator
recorded no failed checks. The M6 reproducibility baseline is committed, and S1
of the selectable-session plan is physically verified. Runs
`20260922-073620-56102` and `20260922-080145-91129` prove the separated
lifecycle/service orchestration still renders Quattro, publishes telemetry and
agent state, executes correlated fixed actions, archives evidence, and returns
to GDM. The S2 seat probe and reversible GDM Wayland experiment also passed;
the next stage is the fixture-tested narrow session service and wrapper.

## Current position

The preferred architecture remains a user-space Ubuntu adaptation that
preserves L4T, JetPack, CUDA, TensorRT, and the NVIDIA graphics stack. Quattro
runs as an explicit, disposable lab session; GDM remains the normal desktop.

The MVP orchestration loop is implemented, physically accepted, and committed
as the reproducible maintenance baseline. The next delivery track is the
staged, reversible integration of an explicitly selectable GDM session without
expanding the accepted MVP claim or weakening the normal Ubuntu recovery path.

## Documents

- [Baseline](docs/BASELINE.md)
- [Quattro architecture](docs/QUATTRO_ARCHITECTURE.md)
- [Compatibility matrix](docs/COMPATIBILITY_MATRIX.md)
- [Package mapping](docs/PACKAGE_MAPPING.md)
- [Hyprland on Jetson](docs/HYPRLAND_JETSON.md)
- [Quickshell](docs/QUICKSHELL.md)
- [Agent integration](docs/AGENT_INTEGRATION.md)
- [Porting options](docs/PORTING_OPTIONS.md)
- [Risks](docs/RISKS.md)
- [Phase 1 plan](docs/PHASE_1_PLAN.md)
- [Phase 3 stability plan](docs/PHASE_3_PLAN.md)
- [Phase 4 lab capabilities plan](docs/PHASE_4_PLAN.md)
- [MVP implementation plan](docs/MVP_IMPLEMENTATION_PLAN.md)
- [Quattro lab startup](docs/STARTUP_WORKFLOW.md)
- [MVP maintenance baseline](docs/MVP_MAINTENANCE.md)
- [Selectable GDM session plan](docs/SESSION_INTEGRATION_PLAN.md)
- [GDM/logind feasibility decision](docs/SESSION_INTEGRATION_DECISION.md)
- [Reversible GDM Wayland experiment](docs/GDM_WAYLAND_EXPERIMENT.md)
- [Narrow GDM session service](docs/GDM_SESSION_SERVICE.md)
- [S3 session-service security review](docs/S3_SECURITY_REVIEW.md)
- [Opt-in Quattro GDM session entry](docs/GDM_SESSION_ENTRY.md)

## Status

The current baseline has physically verified Quattro rendering, input, audio,
notifications, filtered connectivity visibility, Jetson power and telemetry,
Codex usage visibility, a workload registry, GDM restoration, and reboot
resilience. See [docs/LAB_VISIBILITY.md](docs/LAB_VISIBILITY.md) for retained
results.

The delivery sequence and exact MVP gates are defined in
[docs/MVP_IMPLEMENTATION_PLAN.md](docs/MVP_IMPLEMENTATION_PLAN.md). New panels
and providers are intentionally frozen until the end-to-end MVP gate passes.

Before any physical display test, run:

```sh
./scripts/check-syntax.sh
```

Start the lab only from the Jetson's physical text console using the workflow
in [docs/STARTUP_WORKFLOW.md](docs/STARTUP_WORKFLOW.md). The repository must not
install generic NVIDIA drivers, alter the kernel/firmware/JetPack stack, replace
GDM, introduce Arch package management, or run an Omarchy installer.

For MVP orchestration, the safe non-display checks are:

```sh
./scripts/quattro-mvp.py preflight
./scripts/quattro-health-report.sh --host
./scripts/quattro-health-report.sh --latest
./scripts/quattro-mvp.py status --run-id RUN_ID
./scripts/quattro-mvp.py evaluate --run-id RUN_ID
# Add --write-result only when intentionally recording the evaluation artifact.
```

The host-side agent adapter requires an explicit approval flag and a specific
archived run. It may inspect and repair this repository, but it cannot perform
the physical VT handoff:

```sh
./scripts/quattro-agent-adapter.sh --run-id RUN_ID --approve
```

During a physical session, the Agents panel keeps MVP-agent state separate from
usage-refresh feedback. After approval it reports `waiting`; exit Quattro
normally and the detached adapter starts Codex only after the full archive is
written and GDM is restored. Follow `agent-run.json` over SSH for the terminal
`completed`, `waiting-for-human`, or `failed` result. The run ID is preserved
through `sudo`, and labelled stopped containers are recovered into that same
evidence bundle on the next launch.

Use the physical start command and the bundled visual checklist before marking
an archived run complete. See [docs/MVP_IMPLEMENTATION_PLAN.md](docs/MVP_IMPLEMENTATION_PLAN.md)
for the full sequence and artifact contract.

## From lab workflow to normal login

The next delivery target is an **explicitly selectable**
`Quattro (Jetson preview)` session at GDM, not boot-time or automatic Quattro.
The current launcher cannot safely be placed behind a GDM desktop entry because
it stops GDM, switches VTs, and performs privileged container setup. The staged
design separates common orchestration from the physical-VT mechanism, proves
GDM/logind seat permissions, introduces only a fixed allowlisted session
service if needed, and then adds a reversible session entry. See
[docs/SESSION_INTEGRATION_PLAN.md](docs/SESSION_INTEGRATION_PLAN.md).

Until that plan reaches its physical acceptance gate, the only supported start
path remains `./scripts/start-quattro-lab.sh` from a local text console. Making
Quattro the preferred session, enabling automatic login, or starting it at boot
remains an explicit future safety decision rather than part of this plan.

The S2 read-only probe found that the logind seat and device model support the
planned narrow host-service architecture. Reversible experiment
`20260922-090045` then verified normal Ubuntu Wayland and Xorg sessions,
NVIDIA/CUDA health, GDM recovery, and byte-for-byte restoration of the original
GDM configuration. S2 is complete; the fixed, allowlisted S3 host service,
runtime supervisor, and unprivileged wrapper are implemented and pass their
fixture/security gates. The temporary service is installed for its approved
health checkpoint but remains static rather than boot-enabled. See
[docs/SESSION_INTEGRATION_DECISION.md](docs/SESSION_INTEGRATION_DECISION.md).

The approved temporary service checkpoint uses the reversible, hash-protected
conductor documented in
[docs/GDM_SESSION_SERVICE.md](docs/GDM_SESSION_SERVICE.md). It never enables the
service at boot and does not change or restart GDM.

The checkpoint passes: the installed hashes, static unit state, active
service, socket ownership/mode, and fail-closed peer authorization were verified.
Visible compositor acceptance remains an S4 physical GDM-session test.

The S4 entry is transactionally installed. Its first physical start attempt
failed closed before runtime launch because the confined service could not read
the wrapper's process environment. The repository fix now validates GDM's
root-owned AccountsService selection while retaining peer/logind/cgroup checks.
A follow-up physical retry reached the Quattro shell, but also exposed a
response-timeout/disconnect race; its fixture-tested reliability fix awaits an
installed-bundle refresh before the final acceptance retry. S4 adds only an
explicitly selected
`Quattro (Jetson preview)` entry and does not change the remembered/default
session, automatic login, GDM policy, or boot enablement. See
[docs/GDM_SESSION_ENTRY.md](docs/GDM_SESSION_ENTRY.md).
