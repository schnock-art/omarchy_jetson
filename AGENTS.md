# Jetson Quattro contributor and agent instructions

These instructions apply to every task in this repository. The project is a
reversible Ubuntu/JetPack adaptation of the Omarchy Quattro experience for a
Jetson AGX Orin. It is not an Arch port and must not compromise the normal GDM
desktop or the NVIDIA software stack.

## Read before changing code

Start with the smallest relevant set of documents:

1. `README.md` for the supported workflow and current status.
2. `docs/MVP_IMPLEMENTATION_PLAN.md` for milestone scope, contracts, and
   acceptance gates.
3. `docs/STARTUP_WORKFLOW.md` before changing session lifecycle code.
4. `docs/QUATTRO_ARCHITECTURE.md` and `docs/AGENT_INTEGRATION.md` before
   changing shell or agent boundaries.
5. The relevant phase/result document when modifying an existing capability.

Treat phase result documents and archived run artifacts as historical evidence.
Do not rewrite past observations to make the current implementation appear
cleaner.

## Non-negotiable safety boundaries

- Keep GDM as the normal desktop. Do not create an autostart session, replace
  the display manager, or make Quattro the boot/login default.
- A physical local VT is required for display handoff. SSH is for observation,
  implementation, diagnostics, and recovery—not for remotely initiating a
  physical session.
- Treat `/home/looco/omarchy` as read-only source material. Runtime adaptation
  belongs in this repository or a disposable copy.
- Preserve Ubuntu, L4T, JetPack, CUDA, TensorRT, the Tegra kernel, firmware,
  boot configuration, and NVIDIA userspace. Do not install generic NVIDIA
  drivers or introduce Arch package management.
- Do not run an Omarchy installer on the host.
- Do not expose provider credentials, a writable host home, the Docker socket,
  or an unrestricted host/system bus to a desktop container.
- Do not add a generic command, shell, arbitrary argument, or arbitrary prompt
  channel from QML to the host.
- Do not infer visual success from logs. Rendering, layout, input, and physical
  display behavior require an explicit human observation.
- Preserve archived evidence under `artifacts/quattro-runs/`. Never delete or
  rewrite material run evidence as part of cleanup or a later report.

If a requested change requires crossing one of these boundaries, stop and ask
for an explicit design decision instead of quietly widening authority.

## Architecture rules

Keep the project split into four clear planes:

1. **Host control plane:** lifecycle, credentials, agent execution, repository
   writes, deterministic evaluation, and archival.
2. **Quattro presentation plane:** sanitized read-only state and explicitly
   confirmed allowlisted actions.
3. **Agent execution plane:** a host/external process scoped to this repository;
   it never runs as part of the Quickshell container.
4. **Evidence plane:** immutable per-run inputs, logs, snapshots, results, and
   revision metadata.

Dependencies point inward toward stable data contracts. QML must not know how
host data is collected, and collectors must not know how panels render it.
Reports and agents must consume the same acceptance contract rather than keep
their own milestone lists.

Use explicit, versioned JSON records at process/container boundaries. Validate
input before acting, write records atomically (`temporary file` then `rename`),
use bounded timeouts, and fail closed on malformed or unknown versions. A
request identifier must correlate every action with exactly one terminal
result. Never execute a command or arguments supplied by a request record.

Archived-run evaluation must use only files inside the selected run bundle.
Do not follow an archived container mount back to `/tmp` or depend on retained
Docker state.

## Clean code expectations

- Prefer a small cohesive script/module with one responsibility over adding
  more conditionals to an unrelated launcher.
- Keep policy (allowed actions, acceptance requirements, state transitions)
  separate from mechanism (Docker, file I/O, QML rendering).
- Define shared constants and contracts once. Do not duplicate log milestones,
  fatal patterns, action names, or schema rules across scripts.
- Make operations idempotent where practical. Re-running status, evaluation,
  cleanup, or archival must not corrupt state or duplicate an action.
- Quote shell expansions, use `set -eu` or stricter semantics when appropriate,
  avoid `eval`, and do not construct executable shell from data.
- Keep privilege narrow and visible. Run as the desktop user unless a specific
  existing display/container operation requires elevation.
- Preserve useful failure context and return meaningful nonzero exit codes.
  Never hide a required check behind `|| true` without recording the failure.
- Use stable repository-relative paths inside evidence and portable scripts;
  use absolute paths only where the host integration explicitly requires this
  known Jetson checkout.
- Keep QML adapters declarative and thin. Collection, policy, parsing
  normalization, and host mutations belong outside the UI.
- Comment why a safety or compatibility workaround exists, not what an obvious
  line does. Reference the relevant evidence/result document when useful.
- Do not refactor unrelated working code during a scoped task.

## Task execution workflow

For every task:

1. **Establish state.** Read the applicable plan section, inspect `git status`,
   and identify existing user changes. Do not overwrite unrelated work.
2. **State the slice.** Identify the milestone/task, expected artifacts, safety
   boundary, and acceptance condition before editing.
3. **Inspect first.** Trace the current data/lifecycle path and reuse existing
   helpers or contracts where they are sound.
4. **Implement the smallest complete vertical change.** Include error,
   timeout, interruption, and cleanup behavior—not only the happy path.
5. **Test proportionally.** Run fast/static checks first, then host fixture or
   integration tests. Do not perform a physical handoff unless it is required
   and the human is at the local VT.
6. **Record evidence.** Preserve outputs needed to reproduce the conclusion.
   Separate facts proven automatically from facts requiring human observation.
7. **Update active documentation.** Change the plan/status/workflow in the same
   task when behavior or an operator command changes.
8. **Report the next state.** Summarize what changed, checks run, evidence,
   remaining risks, and the exact next gate. Do not say a milestone is complete
   while required physical or human acceptance remains pending.

Do not start later milestone work merely because it is nearby. Finish or
explicitly defer the current acceptance gate first. New panels, providers, and
polish remain frozen until the MVP end-to-end gate in the implementation plan
passes.

## Required checks

Before any physical display test, always run:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/check-syntax.sh
```

`start-quattro-lab.sh` and `run-hyprland-drm.sh` also run this gate. If it
fails, do not stop GDM or hand the VT to Hyprland; fix the failure first.

For non-display work:

- run `./scripts/check-syntax.sh` after changing shell, QML, manifests, or
  runtime configuration;
- run the narrowest relevant fixture/integration tests for changed control
  logic;
- exercise normal, malformed, timeout, duplicate, and interruption cases for
  boundary protocols; and
- verify archived-run tooling after live temporary directories and containers
  are unavailable.

Do not treat syntax validation as behavioral acceptance. Conversely, do not
repeat a physical test for changes that fixture-based host tests can prove.

## Physical-test procedure

- The human starts the session from the Jetson's local text console.
- Keep an SSH connection available for observation and recovery.
- Use the documented launcher; do not manually reproduce a partial GDM/VT
  sequence unless diagnosing that launcher.
- Bundle completed changes into one planned visual checkpoint.
- Record the Git revision, exact command, observed assertions, exit behavior,
  and archive path.
- On failure, prioritize restoring GDM and preserving evidence before editing.

## Evidence and status language

Use these terms precisely:

- **implemented:** code exists and relevant non-physical checks pass;
- **ready for physical test:** preflight passes but display/input behavior is
  not yet observed;
- **physically verified:** a human observed the specified acceptance checks and
  the run evidence is retained;
- **MVP complete:** the full archived-run acceptance contract passes, including
  required human assertions and GDM restoration.

Warnings, unavailable data, zero values, expected shutdown signatures, and
failures are distinct states. Preserve that distinction in schemas, UI, logs,
and summaries.

## Definition of done

A change is done only when its acceptance condition is met, relevant checks
pass, evidence is retained, active documentation matches behavior, and no
required physical validation is being implied as complete. The repository must
remain recoverable, with GDM as the normal desktop and all safety boundaries
above intact.
