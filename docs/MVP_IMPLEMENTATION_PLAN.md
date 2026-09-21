# Quattro Jetson MVP implementation plan

## Objective

Deliver a repeatable Quattro lab session in which a human performs the one
required physical-VT handoff and a host-side coding agent can complete the
remaining setup, automated acceptance checks, diagnosis, and evidence
collection.

The MVP is an operational loop, not another collection of individually tested
widgets:

```text
human starts the session on a physical VT
                  |
                  v
human observes the bundled visual checks and approves the agent
                  |
                  v
Quattro exits normally, GDM returns, and evidence is archived
                  |
                  v
detached agent observes the completed archive
                  |
                  v
agent runs fixed checks and approved scenarios
                  |
                  v
agent records PASS/FAIL or the exact remaining human gate
```

## Current baseline

The difficult platform work is already proven:

- Hyprland renders on the Jetson NVIDIA DRM/GBM/EGL stack;
- Quickshell loads the real Omarchy Quattro shell on ARM64;
- physical keyboard and mouse input work;
- audio, notifications, filtered network and Bluetooth access, Jetson power
  status, telemetry, agent usage, and the workload registry have been exercised;
- normal exit restores GDM;
- reboot resilience has passed; and
- physical run logs are archived under `artifacts/quattro-runs/`.

The remaining gap is orchestration. Current scripts can launch, observe, and
recover the lab, but there is no single machine-readable definition of a good
run and no durable session record that tells an agent what to do next.

## MVP boundary

### In scope

- one explicit command from a physical VT to start the lab;
- a machine-readable acceptance contract;
- a session state machine with bounded timeouts;
- immutable evidence for each completed run;
- separate host-readiness, live-session, and archived-run reports;
- a session-scoped, allowlisted request/result protocol;
- a host-side adapter for one explicitly configured coding agent;
- automated non-visual acceptance checks and diagnosis;
- one bundled human visual checkpoint;
- clean exit to GDM and a final PASS/FAIL verdict.

### Out of scope

- making Quattro the default login session or starting it at boot;
- unattended physical VT or GDM handoff;
- a generic command, terminal, or arbitrary prompt channel from QML;
- placing provider credentials or a writable host home in a container;
- installing Arch packages or the Omarchy installer;
- changing JetPack, the NVIDIA driver stack, kernel, firmware, or boot flow;
- automatic fixes outside this repository; and
- additional providers, local inference, or new panels until the MVP gate is
  green.

## Architecture and trust boundaries

### 1. Host control plane

The host owns orchestration, credentials, repository changes, agent processes,
test evaluation, lifecycle management, and evidence archival. New control
logic belongs in host-side scripts or a small, cohesive host-side program.

The host control plane must run as the desktop user wherever possible. Existing
privileged display/container operations remain narrow and explicit. It must not
turn the Quickshell container into a privileged control environment.

### 2. Quattro presentation plane

Quattro displays sanitized state and offers explicitly confirmed, allowlisted
actions. QML must not construct host commands, accept arbitrary arguments, or
receive provider credentials. UI adapters should render records and submit
versioned action identifiers only.

### 3. Agent execution plane

The coding agent runs on the host or an external control session, rooted at
this repository. It may inspect evidence, change repository files, run safe
checks, and prepare the next physical test. It must follow `AGENTS.md` and may
not initiate a physical display handoff remotely.

### 4. Evidence plane

Every run receives a stable run ID and directory. Evidence is copied into that
directory before temporary mounts are removed. A report about an archived run
must depend only on the archive, not on a path under `/tmp` or retained Docker
container state.

## Required contracts

The field names below are a starting contract. During implementation they may
be extended compatibly, but their meaning must remain stable and documented.

### Acceptance manifest

Add a versioned manifest such as `mvp/acceptance.json` containing:

```json
{
  "schemaVersion": 1,
  "requiredMilestones": [],
  "fatalPatterns": [],
  "scenarios": [],
  "visualAssertions": [],
  "timeouts": {},
  "requiredArtifacts": []
}
```

Both the conductor and archived-run report must evaluate this contract. Avoid
duplicating milestone lists in multiple scripts.

### Session record

Persist a sanitized record shaped like:

```json
{
  "schemaVersion": 1,
  "runId": "YYYYMMDD-HHMMSS",
  "revision": "git revision",
  "state": "preflight",
  "stateChangedAt": "ISO-8601 timestamp",
  "startedAt": "ISO-8601 timestamp",
  "completedAt": null,
  "result": null,
  "reason": null
}
```

Allowed states are:

```text
preflight
ready-for-handoff
starting
ready
testing
awaiting-visual-check
passed
failed
restoring-gdm
complete
```

Transitions must be validated. Terminal failure must include a concise reason
and evidence location. An interrupted run must never remain indefinitely in a
running state.

### Action request and result

Each request must be a distinct atomic file or record with at least:

```json
{
  "schemaVersion": 1,
  "requestId": "unique opaque ID",
  "action": "run-mvp-acceptance-v1",
  "requestedAt": "ISO-8601 timestamp"
}
```

The corresponding result must include `requestId`, `action`, `state`,
`startedAt`, `finishedAt`, `message`, and a relative evidence path. Requests
must be processed at most once. Unknown versions, malformed records, duplicate
IDs, symlinks, and unexpected fields must fail closed and leave an audit entry.

Initial allowlisted actions are:

- `run-mvp-acceptance-v1`;
- `refresh-codex-status-v1`;
- `run-harmless-sample-v1`;
- `collect-diagnostics-v1`; and
- `request-session-exit-v1` if clean exit can be implemented without widening
  the compositor boundary.

### Archived run bundle

Each `artifacts/quattro-runs/<run-id>/` bundle must contain, when applicable:

- `session.json`;
- `acceptance-result.json`;
- `visual-check.json`;
- the acceptance manifest version or an exact copy;
- Git revision and dirty-worktree metadata;
- Hyprland and Quickshell logs and container inspection data;
- sanitized agent-status, telemetry, workload, and action snapshots;
- scenario results with timestamps and evidence references; and
- a human-readable `summary.txt`.

Temporary directories may be removed only after required snapshots are copied
successfully. Archives remain local and must not be rewritten by later reports.

## Delivery milestones

Each milestone should be a reviewable change that leaves the existing launcher
usable. Do not combine all milestones into one rewrite.

### Milestone tracker

This table is the active delivery tracker. Update it only when the stated gate
has evidence; use the status vocabulary defined in `AGENTS.md`.

| Milestone | Status | Next gate |
| --- | --- | --- |
| M0 — Baseline | Physically verified | Run `20260922-063507-9503` retained the combined display, panel, input, exit, telemetry, and agent evidence |
| M1 — Durable evidence | Physically verified | Run `20260921-212029-16341` retained snapshots, agent state, and both labelled-container logs in one bundle |
| M2 — Acceptance conductor | Physically verified | Offline evaluation of run `20260922-063507-9503` passed with no failed checks |
| M3 — Action protocol | Ready for physical test | Confirm usage refresh no longer replaces the dedicated MVP-agent status |
| M4 — Agent adapter | Physically verified | Detached Codex survived normal exit, evaluated the completed archive, and stopped at the human gate |
| M5 — End-to-end proof | MVP complete | Run `20260922-063507-9503` is `complete` with a passing stored acceptance result and human visual evidence |
| M6 — Handoff | Implemented | Commit the documented baseline to `main`, record that commit in `docs/MVP_MAINTENANCE.md`, and verify the clean committed tree |

When a milestone is not complete, record the exact next gate rather than a
percentage. If work must proceed out of order, note the dependency and do not
claim the later milestone is accepted until its prerequisite evidence exists.

### M0 — Validate and freeze the baseline

Purpose: establish the precise starting point and stop feature drift.

Tasks:

1. Run the syntax gate.
2. Perform one combined physical checkpoint for the current revision.
3. Exercise the harmless workload action, Codex refresh, visible action
   feedback, and telemetry source age.
4. Exit normally and retain the health report and run evidence.
5. Record any genuine regression separately from evidence-reporting defects.
6. Freeze new panels/providers until M5 passes.

Acceptance:

- GDM returns normally;
- the latest UI action batch has physical evidence;
- the run has an unambiguous revision; and
- known failures are recorded with reproduction steps.

Human gate: one physical session.

### M1 — Durable evidence and truthful reporting

Purpose: eliminate reports that mix live state, deleted temporary paths, and
old archives.

Tasks:

1. Copy sanitized runtime snapshots into the run bundle before cleanup.
2. Add explicit report modes:
   - `--host` for current host readiness;
   - `--live` for active containers and live mounts;
   - `--run <run-id>` for one immutable archive; and
   - `--latest` for the newest completed archive.
3. Ensure `--run` works after containers and `/tmp` directories are gone.
4. Record the evaluated revision and evidence source in every report.
5. Add fixtures for a good archive, incomplete archive, malformed snapshot,
   failed compositor, and expected Wayland shutdown.

Acceptance:

- archived reports read only their selected bundle;
- a deleted live mount cannot turn a previously good archive red;
- missing required evidence is reported as missing, never inferred as success;
- report exit codes and PASS/WARN/FAIL policy are documented and tested.

Human gate: none.

### M2 — Acceptance contract and conductor

Purpose: give humans, scripts, and agents one definition of completion.

Tasks:

1. Add the versioned acceptance manifest.
2. Implement a conductor command with at least `preflight`, `status`,
   `evaluate`, and `finalize` operations.
3. Persist and validate session-state transitions atomically.
4. Move shared milestone and fatal-pattern evaluation out of ad hoc report
   branches into reusable logic.
5. Produce both JSON and concise human-readable output.
6. Make repeated `status` and `evaluate` operations idempotent.

Acceptance:

- the same evidence produces the same verdict offline;
- invalid state transitions fail without corrupting the previous record;
- every failure identifies the failed check and its evidence;
- syntax/static tests cover manifest validation and state transitions.

Human gate: none.

### M3 — Correlated allowlisted actions

Purpose: turn the current single shared status file into a reliable protocol
without introducing arbitrary execution.

Tasks:

1. Introduce request IDs and per-request results.
2. Validate schemas and action versions before dispatch.
3. Retain the fixed mapping from action ID to implementation; never execute a
   command supplied by the requester.
4. Add bounded timeouts, duplicate suppression, cleanup, and audit logging.
5. Update panels to display only results matching the action/request they
   submitted.
6. Add tests for valid, unknown, malformed, duplicate, timed-out, and
   interrupted requests.

Acceptance:

- a Codex refresh result cannot appear as a workload result;
- every accepted request reaches exactly one terminal state;
- unknown or malformed input causes no host action;
- gateway termination leaves active fixed workloads truthfully marked.

Human gate: one bundled visual confirmation with M5, not a separate session.

### M4 — Host-side agent adapter

Purpose: allow an explicitly selected coding agent to finish the safe,
non-visual portion of setup and testing.

Tasks:

1. Add a provider-neutral adapter interface and one Codex implementation.
2. Launch in `/home/looco/repos/omarchy_jetson` as the desktop user.
3. Supply a fixed objective containing the run ID, acceptance command, safety
   boundaries, and expected final-output location.
4. Publish sanitized agent state: `unavailable`, `ready`, `running`,
   `waiting-for-human`, `completed`, or `failed`.
5. Add a lock so only one MVP agent owns a run.
6. Bound runtime and preserve logs; provide an explicit stop/recovery path.
7. Require a visible confirmation before launch. Do not silently inherit
   upstream broad auto-approval behavior.
8. If no supported agent is installed or authenticated, report that as a
   readiness failure with a manual recovery instruction.
9. Preserve the run ID across privilege changes and label runtime containers
   so delayed recovery archives evidence into the originating bundle.
10. Treat timeout, signal, and an explicit stop as terminal agent results;
    recursively stop the owned process group and never retain stale `running`.
11. Keep provider refresh and MVP-agent state in separate records so an
    unrelated action cannot hide agent progress.
12. After explicit approval, detach the bounded adapter, wait for normal
    Quattro exit and archival, then start Codex against the completed bundle.
13. Make stopped-container recovery atomic and independent of an existing
    artifact's owner; normalize completed bundles to the desktop user.
14. Resolve a structured `waitingFor: visual-check` gate only after a passing
    human record, then require a passing stored evaluation before transitioning
    the session to `complete`.

Acceptance:

- the adapter can run preflight, inspect evidence, evaluate a run, and write a
  final result without credentials entering Docker;
- it cannot launch from an unversioned or arbitrary QML request;
- it pauses at physical/visual gates rather than bypassing them;
- stopping the adapter does not stop recovery or GDM restoration.

Human gate: explicit agent launch approval.

### M5 — End-to-end MVP acceptance

Purpose: prove the complete operational loop.

Tasks:

1. Start from the physical VT with one documented command.
2. Confirm the conductor reaches `ready` within its timeout.
3. Record one consolidated visual checklist covering only assertions that
   cannot be established from logs or IPC.
4. Approve the configured agent through the allowlisted action and observe its
   independent `waiting` state.
5. Exit Quattro normally, restore GDM, and finalize the archive.
6. Let the detached adapter run all automated scenarios against that archive.
7. Record the agent and deterministic evaluator's terminal result.
8. Repeat once after a normal reboot if lifecycle code changed after the prior
   reboot-resilience proof.

Acceptance:

- one run receives a final PASS with all required artifacts;
- intentional failure of one fixture produces a specific FAIL;
- GDM is restored after success and handled failure;
- the final report can be regenerated using only the archived run bundle;
- the agent's conclusion and the deterministic evaluator agree.

Human gate: physical start, explicit agent approval, one visual checklist, and
normal exit.

### M6 — MVP handoff and maintenance baseline

Purpose: make the result understandable and repeatable without project
archaeology.

Tasks:

1. Update `README.md` with the supported workflow and current limitations.
2. Consolidate startup, observation, recovery, and report commands.
3. Mark superseded phase-plan statements as historical rather than deleting
   useful evidence.
4. Document schema compatibility and how to add an action or provider.
5. Record the known-good image names, upstream Omarchy revision, and MVP Git
   revision.

Acceptance:

- a new operator can identify the correct start, status, recovery, and report
  commands from the README;
- active documentation does not describe already completed work as blocked;
- all required checks pass from a clean checkout with the retained images.

Human gate: documentation review only.

The M6 handoff material is consolidated in
[MVP_MAINTENANCE.md](MVP_MAINTENANCE.md). The next-stage path to an explicitly
selectable GDM session is intentionally separate in
[SESSION_INTEGRATION_PLAN.md](SESSION_INTEGRATION_PLAN.md); it does not expand
the MVP acceptance claim or make Quattro the boot/login default.

## Test strategy

### Fast gate

`scripts/check-syntax.sh` remains mandatory before physical work. Extend it to
validate new shell scripts, JSON schemas/manifests, and fixture structure. It
must remain safe, deterministic, and free of display changes.

### Host integration tests

Use temporary directories and fixture archives. Cover state transitions,
atomic writes, archive selection, action dispatch, timeouts, duplicate
requests, interruption, and report exit codes. Tests must not require stopping
GDM or accessing a physical VT.

### Container/preflight tests

Use existing image and Quickshell configuration verification where relevant.
Do not treat a successful QML parse as proof of visible rendering.

### Physical acceptance

Bundle visual checks by completed milestone. Before every physical run:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/check-syntax.sh
```

Only the human at the local VT initiates display handoff. Keep SSH available
for observation and recovery. Never invent a visual PASS from logs.

## Definition of done for every implementation task

A task is complete only when:

- its scope and acceptance condition are satisfied;
- safety and trust boundaries remain intact;
- normal, malformed, timeout, and interruption paths are considered;
- relevant automated checks pass;
- physical validation is recorded when the change affects rendering, input,
  compositor lifecycle, or the host/container boundary;
- evidence and active documentation are updated in the same change;
- no unrelated user work is overwritten; and
- the task leaves a concise next-state note if later work remains.

## Recommended implementation order

The critical path is:

```text
M0 baseline
  -> M1 durable evidence
  -> M2 acceptance conductor
  -> M3 action protocol
  -> M4 agent adapter
  -> M5 end-to-end proof
  -> M6 handoff
```

M1 and the fixture design for M2 may be prepared together, but the conductor
must not depend on ephemeral evidence. The agent adapter comes after the
deterministic evaluator so the agent cannot become the sole judge of success.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Agent or UI becomes a generic host command path | Versioned action allowlist; no caller-supplied command or arguments |
| Archived reports depend on deleted `/tmp` data | Copy snapshots before cleanup; archive-only report mode |
| Agent claims visual success | Explicit `awaiting-visual-check` state and recorded human assertion |
| GDM is not restored after failure | Preserve launcher traps, bounded stages, SSH recovery, and lifecycle fixtures |
| Two agents or requests race | Per-run ownership lock, atomic request/result files, duplicate IDs rejected |
| Documentation drifts from implementation | Update active docs and acceptance contract in the same task |
| Upstream Omarchy changes unexpectedly | Record upstream revision and keep `/home/looco/omarchy` read-only |
| Broad agent auto-approval exceeds MVP authority | Dedicated adapter policy and explicit launch approval |
| Ubuntu blocks Codex's private network namespace | Retain `workspace-write`; share command networking; never fall back to full host access |

## Decisions recorded for M4

The first physical agent attempt resolved the initial choices as follows:

1. launch a dedicated non-interactive `codex exec` process;
2. cap Codex runtime at 30 minutes, cap the pre-archive wait at two hours, and
   retain an explicit per-run stop command;
3. retain the existing keyboard exit for MVP rather than granting QML a session
   exit action; and
4. keep the bundled visual checklist as a separate human-recorded artifact.

The 2026-09-21 attempt exposed and retained three defects: the run ID was lost
through `sudo`, interrupted Codex state remained `running`, and Ubuntu blocked
Bubblewrap's private loopback setup. The control-plane fixture now covers the
first two, while a bounded Codex probe verified the documented network-sharing
compatibility override without removing the workspace filesystem sandbox.
The following run proved truthful interruption but also showed that a
session-scoped agent cannot evaluate evidence that is only archived on exit.
The adapter is now detached after approval, waits for the completed archive,
and begins Codex only after GDM restoration. Refresh status and MVP status are
separate records.
