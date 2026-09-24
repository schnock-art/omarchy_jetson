# Phase 4 — Jetson lab capabilities

## Aim

Build on the stable Quattro lab baseline and turn it into a useful control and
observation surface for real Jetson work. The priority is operational clarity:
what agents are available, what workloads are using the device, and whether
the lab is healthy—without replacing GDM, exposing credentials to containers,
or enabling unattended agent actions by default.

## Operating model

```text
Host services and credentials  -> host-side, least privilege
Sanitized status snapshots     -> read-only mounts into Quattro
Quattro panels                 -> display and explicitly approved controls
Physical display testing       -> one checkpoint per completed batch
SSH / Codex                    -> implementation, checks, logs, recovery
```

## Batch 4A — Agent observability

### Outcome

Turn the working Codex bridge into a useful, truthful agent panel rather than
only a few counters.

### Scope

- display Codex plan/tier, usage freshness, short/weekly limit windows, and
  today/total prompts from the existing sanitized host record;
- show an explicit state for unavailable, stale, unauthenticated, or failed
  collection rather than blank values;
- record the source timestamp and refresh age;
- extend the health report to distinguish a valid but zero-usage record from
  a missing or failed record;
- keep provider launch, credentials, and background work outside the panel.

### Acceptance

One physical test: the Agents panel shows a non-empty Codex record, freshness,
and any real limit window. The SSH health report confirms the same record.

### User input

None until the single visual check.

## Batch 4B — Workload telemetry

### Outcome

Make the existing telemetry panel useful during AI/compute experiments.

### Scope

- retain a short in-memory history of CPU, GPU, RAM, thermals, and input power;
- show simple current/peak/trend values, not a persistent host database;
- identify collector staleness and distinguish unavailable sensors from zero;
- preserve the existing read-only `tegrastats` and `nvpmodel` boundary.

### Acceptance

One physical test while a normal workload is running: values refresh and the
history visibly changes. No power mode or fan control is introduced.

### User input

Start any ordinary workload only if convenient; otherwise the batch can use
idle telemetry and remain partially verified.

## Batch 4C — Lab workload registry

### Outcome

Expose a concise read-only list of deliberate lab jobs: name, state, owner,
start time, resource notes, and log path.

### Scope

- define a small host-side JSON registry and a CLI for registered jobs;
- support registration by explicitly launched scripts only;
- add a Quattro panel that reads the sanitized registry snapshot;
- include job health in the SSH report;
- no generic process killing, shell execution, or privilege escalation.

### Acceptance

Register one harmless sample job, observe it remotely and in Quattro, and let
it finish naturally. The panel then shows completed state and log location.

### User input

None for the sample job.

### Implemented baseline

The host registry, a fixed harmless sample job, and the read-only Quattro
panel are implemented. Visual confirmation is bundled with the telemetry
history check to avoid a separate physical session.

## Batch 4D — Deliberate agent actions

### Outcome

Add approved actions only after observability and job registration are stable.

### Candidate actions

- open an explicitly configured coding-agent terminal;
- request a refresh of a provider's usage record;
- submit a predeclared lab job through the registry.

Every action requires a visible target, clear user approval, bounded logs, and
a stop/recovery path. No button may silently start a networked agent, modify
the host, or run in the background indefinitely.

### Decision gate

The first approved action is deliberately narrower than provider launch: a
twice-confirmed request to submit the fixed, local harmless sample job through
the existing registry. It has no command field, arguments, credentials,
network access, stop/kill action, or persistence beyond the active Quattro
session. Provider or coding-agent launch still requires a separate user
decision about the agent and authority each receives; it is not implied by
displaying usage data or by this sample action.

### Acceptance

One physical Quattro session: open **LAB WORKLOADS**, select **Start harmless
sample…**, then select the confirmation. The panel should show the new job as
running and then completed after roughly 15 seconds. Exit normally with
Super+Shift+E; the usual SSH health report should pass. If the session ends
before completion, the registry must show the sample as failed rather than
leave it running.

### Follow-up visibility batch

The next combined physical checkpoint adds explicit action feedback, a
twice-confirmed refresh of the existing Codex usage snapshot, and a telemetry
source-age indicator. The refresh only runs the existing host-side collector
once under the desktop user; it launches no coding agent and exposes no
credentials. The same short-lived gateway accepts exactly two fixed request
values and records a sanitized result for the panels.

## Batch 4E — Additional providers

Add Claude, Fireworks, local inference, or other providers one at a time using
the same host-collector/sanitized-record pattern as Codex. Each provider gets
its own authentication, data-retention, and refresh-policy review.

The local-inference/provider implementation path is now explicitly defined in
[LOCAL_BUILDER_PLAN.md](LOCAL_BUILDER_PLAN.md). It supersedes this paragraph as
the scope for Ollama and a local repository builder: loopback-only service,
model benchmark, isolated worktree runner, versioned task/result records, and
twice-confirmed fixed approval are required before a local model can change
repository files.

## Completion criteria

Phase 4 is complete when 4A through 4C pass, agent/workload state is visible
both over SSH and in Quattro, and any interactive agent action remains clearly
opt-in and recoverable.

## Explicit non-goals

- replacing GDM or autostarting Quattro at boot;
- mounting provider credentials or writable host homes into Quattro;
- background autonomous agents without explicit approval;
- a generic unrestricted terminal or shell-execution button;
- changes to JetPack, the NVIDIA driver stack, kernel, firmware, or boot flow.
