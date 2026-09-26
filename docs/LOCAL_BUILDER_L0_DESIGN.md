# Local builder L0 inventory and isolation design

## Scope and result

This document records the 2026-09-26 L0 prerequisites/design-lock work. It
does not install Ollama, pull a model, load AppArmor policy, create a service,
or change GDM/Quattro.

This is a design for the **Repository Builder** role only. Its restrictive
boundary must not be generalized into the capability model for every future
Quattro agent; the role-specific architecture is in
[QUATTRO_ARCHITECTURE.md](QUATTRO_ARCHITECTURE.md). Conversely, future
Desktop/User or System Agent authority does not relax any Builder control in
this document.

**Status: design selected; L0 gate is not yet satisfied.** Bubblewrap plus a
bounded systemd user unit enforces the intended boundary when unprivileged user
namespaces are permitted. The fixed isolation fixture passes in the Codex
desktop AppArmor context. In a normal operator/user-manager process, Ubuntu
AppArmor transitions namespace creation into `unprivileged_userns (enforce)`;
Bubblewrap then loses the capability needed to configure its isolated loopback
and fails closed. The uninstalled, syntax-checked
draft under `local-builder/apparmor/` is the smallest proposed closure, but
loading it is a host-policy change requiring a separate approved checkpoint.

The canonical inventory is
`artifacts/local-builder-l0/20260926-105734/host-inventory.json`. The earlier
`20260926-105653` first probe is retained rather than rewritten; its thermal
command timed out before producing a sample.

## Observed Jetson host inventory

These are point-in-time facts, not capacity promises.

| Area | Observation |
| --- | --- |
| Host | Jetson AGX Orin; Ubuntu 24.04.4 LTS; `6.8.12-1021-tegra`; aarch64. |
| RAM/swap | 65,932,349,440 bytes RAM (61.4 GiB), about 54.5 GiB available; `/swapfile` is 2.0 GiB and unused. |
| Disk/layout | `/`, `/home`, `/tmp`, the checkout, and proposed task roots share `/dev/nvme0n1p1`, ext4: about 915 GiB total and 812 GiB available. `/run` is a roughly 12.3 GiB `tmpfs` with `nosuid,nodev`. No separate evidence filesystem or project-quota mount option was observed. |
| Power/thermal | `MODE_30W`, mode ID `2`. The canonical bounded sample reported CPU/TJ 54–55 C, GPU about 50 C, SoC about 51 C, and GR3D 27–30%. |
| NVIDIA/CUDA | `nvidia-smi` succeeds: driver 595.78, CUDA API 13.2, Orin `nvgpu`, no GPU processes. `nvcc` is 13.2.86; CUDA and TensorRT 10 libraries resolve. This is discovery health, not an inference or sustained thermal benchmark. |
| Ollama | No executable; system and user units are not found/inactive; nothing listens on TCP 11434. No model was queried or downloaded. |
| Bubblewrap | Version 0.9.0, not setuid. User/mount/PID/IPC/UTS/cgroup/network namespace setup works from the Codex profile. `newuidmap`, `newgidmap`, and `slirp4netns` are absent and are not needed for a single-ID, no-network design. |
| AppArmor/LSMs | AppArmor is active/enabled; `capability,landlock,yama,apparmor` are loaded. `apparmor_restrict_unprivileged_userns=1`, `unprivileged_userns_clone=1`, and `user.max_user_namespaces=249375`. Unprivileged `aa-status` cannot enumerate profiles. Codex is `chatgpt (unconfined)` and that installed profile grants `userns`; a normal user-manager process starts `unconfined`, transitions to `unprivileged_userns (enforce)`, and Bubblewrap fails while configuring loopback. |
| Cgroups/systemd | Unified cgroup v2; systemd 255. A transient user unit enforced runtime, control-group kill, task, memory, and no-new-privileges properties. User-unit `PrivateNetwork=yes` did not create a distinct network namespace, so it is not trusted for network isolation. |
| Git/worktrees | Git 2.43.0. The checkout was initially clean at `e752e28ebf22b3d10e42d5a3b528faba3a7e2484`, `main`, with no linked worktree. A disposable fixture created and changed a linked worktree without changing its primary worktree. |
| Existing authority | The user belongs to `sudo`, but not `docker`. `/run/docker.sock` is root:docker 0660 and currently inaccessible. These incidental permissions are not controls: the sandbox hides the socket and makes `sudo` inert. |
| Secondary facilities | Unprivileged BPF is disabled and Yama `ptrace_scope=1`; Landlock is available but no repository launcher exists. The design does not depend on them. |

## Isolation decision

Use a **fixed controller in a bounded transient systemd user service**, with
every model-directed file operation and check performed inside **rootless
Bubblewrap**. Do not use Docker: its privileged daemon and socket widen the
boundary. AppArmor grants only the prerequisite `userns` permission to the
fixed controller; Bubblewrap remains the per-task filesystem/network/process
boundary.

The unit is concurrency-one and fixes `NoNewPrivileges=yes`,
`KillMode=control-group`, `RuntimeMaxSec`, `TasksMax`, `MemoryMax`, and output
limits. Bubblewrap uses the equivalent of:

```text
--unshare-all --unshare-user
--disable-userns --assert-userns-disabled
--cap-drop ALL --new-session --die-with-parent --clearenv
```

Its root contains only a small read-only runtime (`/usr` and required loader
data), new `/proc`, synthetic `/dev`, and private tmpfs `/tmp` and `/run`. It
does not bind `/`, `/home`, `/sys`, Docker, D-Bus, GPU devices, SSH agents,
credentials, or primary-checkout files. It binds exactly the task worktree and
task evidence directory read-write, plus Git common/admin metadata and the
worktree `.git` pointer read-only. `GIT_OPTIONAL_LOCKS=0` and empty Git/home
configuration prevent metadata writes. The controller creates the worktree
and later computes the diff; the model cannot stage, commit, merge, or update
refs.

Bubblewrap's network namespace is the network boundary; it cannot reach host
loopback or LAN. The trusted controller may make only the reviewed loopback
Ollama call. Model output is data. Its tool protocol supports bounded
workspace file/patch operations and allowed check IDs, not model-generated
host shell text. Adding any arbitrary-command tool, even inside the sandbox,
requires a new design review.

### AppArmor prerequisite

Ubuntu denies this rootless setup from a normal operator context. The proposed
profile attaches only to the future root-owned
`/usr/libexec/omarchy-quattro/local-builder-controller` and adds `userns,` to
an otherwise unconfined application profile. It grants no sudo, capabilities,
filesystem writes, network, or Docker access. It is not installed because the
fixed path, transactional installation, hashes, and rollback do not exist yet.

Before L1, a reviewed L0 closure must install/test/rollback that exact policy,
make the normal-context fixture pass, prove unrelated unconfined processes
remain denied, and retain profile hashes/status. This needs explicit approval
because it writes host AppArmor policy.

## Threat model and trust boundaries

In scope are malicious/confused/prompt-injected model output; malformed,
duplicate, stale, or extended task records; path/symlink/rename, network,
process, privilege, Docker, and resource escapes; hanging/forking/noisy checks;
model/service loss, signal, timeout, reboot, and partial setup; and a dirty or
mismatched primary checkout.

The trusted computing base is the kernel namespace/LSM/cgroup implementation,
systemd, Bubblewrap, fixed controller/schema, reviewed task-template and check
registries, Git, and exact repository revision. Ollama and model output are
untrusted. Quattro is an approval/presentation client, not a security boundary.
An already compromised desktop-user account, kernel/Bubblewrap exploit, and
physical/root attacker are out of scope. Bundle hashes give audit integrity,
not protection from another malicious same-user process.

- The **host control plane** validates a complete record, selects reviewed
  template/model role, creates worktree/evidence, talks to loopback Ollama, and
  interprets only a narrow tool/result protocol.
- The **sandbox plane** writes only its worktree/evidence and sees no host
  network/processes, capabilities, sudo path, nested userns, or host services.
- The **presentation plane** submits only an allowlisted action and opaque task
  ID—never prompt, command, arguments, path, model tag, or sandbox options.
- The **evidence plane** is task-specific, atomically updated, then sealed and
  hashed; archived evaluation uses only the bundle.

## Task templates and allowed checks

A reviewed `task-template-v1` manifest fixes implementation instructions,
repository-relative allowed paths, model role (not model tag), maximum
turns/runtime/change bytes, and allowed check IDs. A new objective requires a
human-reviewed template first; neither QML nor the action record supplies free
text. `local-builder-task-v1` repeats resolved values for audit, but they must
exactly match the template and unknown/extra fields fail closed.

An `allowed-check-v1` registry maps an ID to exact executable, argv, working
directory, timeout, output cap, and exit policy. Tasks cannot add arguments.
Checks run inside the sandbox; schema, changed-path, diff, and hash validation
are controller-only. Model substitution is separate: templates name a role and
resource class, while a benchmark maps the role to a digest. `qwen3:8b` and
`qwen3-coder:30b` remain candidates, not dependencies.

## Failure, recovery, and retention

One request owns one lock, transient unit, worktree, evidence directory, and
terminal result. Setup failure launches no model work. Timeout/interruption
kills the whole cgroup and captures bounded status/log/diff evidence before
removing only failed-task temporary state. Recovery uses no caller path and
does not follow symlinks. Completed/waiting worktrees remain for review; failed
worktrees may be removed only after durable diff/evidence capture. Evidence is
never automatically deleted; cleanup is exact-ID and idempotent.

Initial L3 limits are one active task, 256 changed files, 32 MiB per file,
256 MiB aggregate model-applied writes, 16 MiB output per check, and 512 MiB
evidence per task. A 20 GiB evidence high-water mark refuses new tasks instead
of pruning. Application limits are required because ext4 project quotas were
not observed. This remains enforceable only while checks are reviewed and the
model has no arbitrary shell.

On reboot, recovery marks nonterminal work `stopped`, verifies no matching unit
remains, and preserves evidence. Ollama loss fails only the task; it never
restarts GDM, Quattro, Docker, or a system service.

## Fixture matrix

| Fixture | Required assertion | L0 result |
| --- | --- | --- |
| Writable scope | Worktree/evidence writable; primary/outside/symlink target unchanged | Passed under Codex profile |
| Mount visibility | No host home, primary files, Docker, D-Bus, `/sys`, credentials, GPU | Core paths passed; complete manifest planned L3 |
| Network | Distinct namespace; no IPv4/IPv6 host loopback or LAN | Passed |
| Privilege | zero capabilities, `NoNewPrivs=1`, sudo fails, nested userns disabled | Passed |
| Processes/lifetime | PID namespace hides host; deadline kills entire cgroup | Passed |
| Git worktree | linked-worktree edit does not alter primary worktree | Passed |
| Operator AppArmor | same sandbox starts from normal user manager | **Failed: L0 blocker** |
| AppArmor scope/rollback | only fixed controller gains userns; exact rollback | Planned L0 closure |
| Generic command/prompt | no command/argv/free-text task fields or host shell tool | Planned L3 contract negatives |
| Check substitution | unknown ID/args/executable/path/duplicate rejected | Planned L3 |
| Filesystem races | `..`, absolute, symlink, hardlink, rename, Git ref escapes fail | Basic symlink passed; matrix planned L3 |
| Network transports | DNS, loopback Ollama, inherited FDs, IPv4/6, outside Unix sockets fail | IP passed; FD/Unix matrix planned L3 |
| Cleanup/retention | timeout/signal/reboot/repeat cleanup preserve sealed evidence | Planned L3 |

Automatically proven here: inventory facts; namespace/mount/capability/sudo/
Docker/basic-symlink/network/Git/cgroup fixture behavior under Codex's profile;
draft AppArmor syntax; and the normal-context denial. Not proven: policy
attachment/rollback, eventual-controller execution, complete mount/FD closure,
contracts/race-safe file operations/evidence recovery, Ollama behavior, or any
model's fit, quality, latency, or thermal stability. L0 needs no physical test.

## Exact next slices

The immediate next slice is **L0 closure**, not L1: implement only the fixed
controller stub and transactional AppArmor profile install/status/rollback,
then run both isolation fixtures from the normal operator path and retain
hashes/evidence. This requires explicit human approval.

Only after it passes, the exact **L1 slice** is: choose/document a reviewed
Ubuntu/aarch64 Ollama source and uninstall path; install no model initially;
add fixed idempotent status/start/stop collection; configure an opt-in service
bound only to `127.0.0.1` and `::1` with no GDM/Quattro/boot dependency; prove
LAN refusal, unavailable/malformed state, stop/restart, and sanitized atomic
status fixtures; then perform one planned read-only status checkpoint. Model
pulls and benchmarks remain L2.
