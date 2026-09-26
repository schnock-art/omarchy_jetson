# Local inference and repository-builder plan

## Decision being scoped

Add an **explicitly approved, host-local** Ollama capability to the Jetson so
an operator can plan with Quattro/Codex and ask a local model to implement one
reviewed repository task. This is a daily-desktop capability track, not a
change to the accepted MVP or to the GDM session lifecycle.

The first implementation target is a local implementation runner for this
repository. It is not an autonomous desktop agent and it is not a general
terminal exposed through Quattro.

Status: **planned; no Ollama package, model, service, or UI action is installed
by this document.**

## Outcome

An operator can:

1. see whether a local model service and selected models are ready;
2. use a fast local model for a bounded planning conversation;
3. review and explicitly approve a structured implementation task; and
4. have a local model work in an isolated Git worktree, run reviewed checks,
   and leave a diff, logs, and a concise result for human review.

The operator, not the model, chooses whether to inspect, commit, merge, run a
physical test, or make a system change.

## Non-negotiable boundaries

- GDM remains the normal desktop. This track does not enable Quattro at boot,
  change a default/remembered GDM session, or introduce automatic login.
- Ollama is a host service bound to loopback only. It is never mounted into the
  Quickshell container and no provider credential, Docker socket, writable host
  home, or host/system D-Bus is exposed to that container.
- Quattro receives sanitized availability, progress, and final-result records.
  It cannot send arbitrary shell text, command arguments, model options, or
  unbounded prompts to the host.
- A local builder may write only its newly created worktree and its own
  per-task evidence directory. It may not write this checkout, `main`,
  `/home/looco/omarchy`, or host configuration.
- The runner must operate as the desktop user, with no `sudo`, Docker access,
  package installation, boot/GDM/JetPack/NVIDIA changes, physical VT handoff,
  or network access during implementation.
- A model result is advisory. Repository checks and explicit human visual
  assertions remain the authority for acceptance.
- One task has one opaque request ID, one worktree, one ownership lock, one
  bounded process group, and exactly one terminal result. Unknown schemas,
  duplicate requests, malformed records, and unexpected fields fail closed.

These restrictions are enforceable control-plane requirements, not merely
instructions inserted into a model prompt.

## Initial model policy

The initial benchmark candidates are:

| Role | Candidate | Why | Decision rule |
| --- | --- | --- | --- |
| Fast planning | `qwen3:8b` | Small enough for responsive local interaction while still useful for repository planning | Install only after the service and disk/readiness checks pass. |
| Bounded implementation | `qwen3-coder:30b` | A coding-focused 30B MoE model; its current Q4 package is approximately 19 GB | Use only if the Jetson benchmark passes within the configured memory, context, latency, and thermal limits. |

These are candidates, not a performance claim. The 30 W Jetson profile and
concurrent desktop workload mean model availability alone is insufficient. The
benchmark must record the exact model digest, quantization, context limit,
power mode, free disk/RAM before and after load, first-token latency,
generation rate, thermal state, and a fixture-task result. If the coding model
does not meet the thresholds, reduce scope or choose a smaller reviewed model;
do not silently overcommit RAM or swap.

Model selection is intentionally decoupled from the runner contract so a model
may be replaced after a recorded benchmark without widening authority.

## Architecture

```text
operator approves a versioned task record
                 |
                 v
host local-builder controller
  validates schema, policy, task template, and repository revision
                 |
       +---------+----------+
       |                    |
       v                    v
Ollama on loopback      dedicated Git worktree + task evidence
       |                    |
       +---------+----------+
                 v
isolated local-model runner (bounded process group)
                 |
                 v
atomic task-result.json, logs, diff summary, test results
                 |
                 v
sanitized read-only status for Quattro and SSH review
```

The controller owns policy and lifecycle. The model sees a fixed task template
and repository context selected by that controller; it does not receive an
arbitrary host prompt channel. The presentation plane renders records and sends
only an allowlisted action identifier plus an opaque, prevalidated task ID.

The worktree is created from a caller-independent, recorded base revision on a
dedicated branch. It is never merged automatically. Before implementation, the
controller must prove the primary checkout is clean or refuse the task rather
than mixing agent work with uncommitted user changes.

## Versioned contracts

The implementation will add small, documented JSON records rather than reuse
the MVP agent record with incompatible meanings.

### `local-builder-task-v1`

The task record will contain at least:

```json
{
  "schemaVersion": 1,
  "requestId": "opaque unique ID",
  "taskKind": "repository-change-v1",
  "templateId": "reviewed template ID",
  "baseRevision": "full Git revision",
  "allowedPaths": ["repository-relative paths"],
  "allowedChecks": ["reviewed check IDs"],
  "model": "reviewed model tag or digest",
  "contextLimit": 0,
  "requestedAt": "ISO-8601 timestamp"
}
```

There is no free-form command, argument list, path outside the repository, or
unreviewed model parameter in this record. The planning transcript is separate
from the implementation record and is not executable input.

### `local-builder-result-v1`

The result will correlate the request and record `queued`, `running`,
`completed`, `waiting-for-human`, `failed`, or `stopped`, timestamps, exact
base revision, worktree-relative evidence paths, changed-path summary, test
results, model identity, and a concise reason. It must be atomically written.
Timeout, interruption, sandbox setup failure, or model-service loss produces a
terminal result and cleans up only that task's process group and worktree.

## Delivery sequence

### L0 — Prerequisites and design lock

Status: **design selected; gate pending.** The 2026-09-26 inventory, threat
model, isolation decision, failure/retention policy, and fixture matrix are in
[LOCAL_BUILDER_L0_DESIGN.md](LOCAL_BUILDER_L0_DESIGN.md). Bubblewrap passes the
fixed boundary fixture from Codex's application profile, but Ubuntu AppArmor
denies the same user-namespace setup from a normal operator context. L1 remains
blocked until the narrow, currently uninstalled controller profile is
explicitly approved and its install, normal-context test, and rollback pass.

- Keep S5 as the display/session reliability prerequisite; local inference must
  not mask a stale session, GDM recovery, or service failure.
- Inventory disk, RAM, swap, power mode, thermals, CUDA/NVIDIA health, existing
  Ollama state, and Bubblewrap/AppArmor capabilities without changing them.
- Decide and document the isolation mechanism that actually enforces the
  worktree-only/no-network boundary. Refuse implementation if that mechanism
  cannot be demonstrated on this Jetson.
- Define task templates, allowed check IDs, retention limits, and stop/recovery
  behavior before adding a UI control.

Gate: a reviewed threat model and fixture plan demonstrate that the proposed
runner cannot become a generic host-command or arbitrary-prompt service.

### L1 — Local Ollama service and truthful status

- Install Ollama only through a reviewed Ubuntu-compatible method, with a
  recorded package/version/source and an uninstall/disable procedure.
- Bind it to `127.0.0.1`/`::1` only; verify it is not reachable on a LAN
  interface.
- Add idempotent `status`, `start`, `stop`, and health collection without
  making the service a GDM, Quattro, or boot-default dependency.
- Pull no model until disk-space, memory-headroom, and download-size checks
  pass. Record model digests after pull.
- Publish a sanitized read-only status snapshot: service state, selected model
  availability, model digest, bounded resource health, and errors. Do not
  publish prompts or model output by default.

Gate: service lifecycle, loopback exposure, unavailable service/model, malformed
status, and stop/restart cases pass fixtures and host checks. A human confirms
the read-only status surface during one planned visual checkpoint.

### L2 — Model benchmark and selection

- Benchmark `qwen3:8b` and, only if headroom remains adequate,
  `qwen3-coder:30b` on fixed non-destructive repository fixtures.
- Set conservative context, concurrency-one, idle-unload, runtime, and thermal
  limits from observed results.
- Publish an immutable benchmark record; do not select a model based solely on
  advertised parameter count or a single successful response.

Gate: the selected model completes the fixed planning and patch-review fixtures
within recorded resource limits, and recovery leaves Ollama usable without
impacting an ordinary Ubuntu session.

### L3 — Isolated repository-builder controller

- Implement fixed task templates and the two JSON contracts above.
- Create a dedicated worktree and branch per task; validate the base revision,
  clean primary checkout, allowed paths, and check IDs before model launch.
- Enforce the reviewed sandbox; disallow network, privilege escalation, Docker,
  writable primary checkout, and paths outside the task worktree/evidence.
- Bound model execution, retain logs/diff/test records, implement exact-task
  stop, and clean failure paths without deleting evidence.
- Add fixtures for valid task, malformed/unknown schema, duplicate request,
  dirty checkout, invalid revision, path escape, model timeout, interruption,
  sandbox failure, test failure, and repeated cleanup.

Gate: a local model makes a small, pre-reviewed repository-only fixture change
in a disposable worktree; the controller proves it cannot alter the primary
checkout or host state. A human reviews the resulting diff before any merge.

### L4 — Quattro approval and review surface

- Add read-only local-model status and task-result adapters to the existing
  Agents panel.
- Add a twice-confirmed allowlisted action to start a previously created,
  validated task record. No text-entry terminal, arbitrary prompt field, model
  picker, or command field is added to QML.
- Show request ID, model identity, bounded progress, stop state, result, test
  summary, and worktree/diff location; keep full logs host-side.
- Provide one fixed stop action for the exact active request.

Gate: physical visual checks prove status clarity, confirmation behavior,
progress/terminal states, and normal logout/recovery. The same task works over
SSH without requiring Quattro.

### L5 — First useful daily workflow

The operator plans a repository task with a selected local model, creates a
structured task from the reviewed plan, approves it, reviews the separate
worktree diff and evidence, and decides manually whether to commit or merge.

Gate: one retained end-to-end example passes the controller contracts and the
human review gate, while normal Ubuntu/Quattro session recovery remains proven.

## Explicit deferrals

- Quattro as default login session, auto-login, or boot-time startup;
- external network providers and provider credentials;
- background scheduling, unattended retries, multi-agent delegation, or
  autonomous merges;
- arbitrary chat-to-shell, arbitrary prompt-to-host, terminal emulation, and
  arbitrary model selection from QML;
- system administration, package installation by the model, and changes to
  NVIDIA/JetPack/GDM/boot state; and
- using an unverified large model merely because it fits on disk.

## Operator workflow after implementation

1. Use the normal Ubuntu or explicitly selected Quattro session.
2. Check local-model health and benchmark status.
3. Plan the task with a human or local planning model; review its structured
   task record.
4. Explicitly approve exactly one implementation request.
5. Review the separate worktree's diff, checks, logs, and terminal result.
6. Decide manually whether to continue, amend, commit, merge, or discard that
   worktree.

No local-model action changes the normal display/session recovery path.
