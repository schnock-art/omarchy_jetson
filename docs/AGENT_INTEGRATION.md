# Agent integration

Quattro’s agent experience is coupled to the Omarchy command and desktop environment, but the useful conceptual pieces are portable: a provider/default-agent abstraction, process launching, environment/context handoff, skills, approval modes, monitoring, and shell-visible controls.

For the Workshop, preserve a distinction between participants and the operating environment. Aster, Codex, Nemotron, humans, and future agents should be peers using shared interfaces—not one model embedded as the OS.

Initial porting should isolate provider launchers and IPC from Arch package management. Do not enable autonomous/background agents during reconnaissance. Jetson CUDA/TensorRT/local inference should remain a separate capability service until the desktop shell boundary is proven.

## Jetson status

Agent integration is deferred but required for the lab. The current Quattro
session deliberately omits the agents widget because the container does not
yet provide the Omarchy agent helper commands (`omarchy-agent-usage-update` and
`omarchy-update-available`). This is a tracked compatibility gap, not a Phase
3 failure and not an out-of-scope feature.

The first implementation target is the smallest useful ARM64-compatible
status/usage bridge and a visible bar widget. Provider launch, approvals,
skills, monitoring, and local CUDA/TensorRT inference will be handled as
separate reviewed batches.

The first bridge is now implemented in the Quattro harness. A host-side
read-only collector reports the number of available usage records and upstream
collectors, while the visible bar panel reports bridge readiness and Codex
usage. It runs Omarchy's existing Codex collector on the host and passes only
the resulting JSON record into the isolated shell; credentials and provider
network access never enter Docker. Provider launching remains explicitly
deferred, and a failed refresh preserves the last valid record.

On this Jetson, Codex Desktop supplies the CLI at
`/usr/lib/chatgpt/resources/codex`, which is not necessarily present in the
reduced environment used by the physical-VT launcher. The host collector,
refresh gateway, and MVP adapter therefore include that fixed installation
directory in their host-only command path. The executable and its credentials
are not mounted into the Quickshell container.

## Codex observability

The first provider batch exposes Codex local usage in the panel: today and
total prompts, sessions, reported tier, refresh age, and a concise primary
limit summary when a live limit window is available. A record with zero usage
is valid and is reported as such; an absent or malformed record is a health
failure. If the local Codex CLI is unavailable, locally derived history remains
visible while the panel states that live provider status is unavailable.

During an active physical Quattro session, the panel also offers a
twice-confirmed **Refresh Codex usage…** request. It runs the same host-side
collector once as the desktop user, replaces only the sanitized status JSON,
and returns a visible action result. It does not launch a coding agent, expose
credentials, create a background process, or grant the shell a generic command
path. The request gateway disappears when the lab session ends.

## MVP acceptance adapter

The MVP adds a separate twice-confirmed **Run MVP acceptance…** action to the
Agents panel. It starts a bounded, detached
`scripts/quattro-agent-adapter.sh` on the host for the current run. The panel
first reports `waiting`: the human exits Quattro normally, the launcher restores
GDM and archives all runtime evidence, and only then does the adapter launch the
configured Omarchy agent. This prevents an agent from diagnosing an archive
that is incomplete merely because the physical session is still active.

For Codex, the adapter uses the supported non-interactive `codex exec` entry
point rather than Omarchy's terminal-oriented launcher. A dedicated
`mvp-status.json` reports `running`, `completed`, `waiting`, or `failed` and is
not replaced by Codex-usage refresh results. Detailed output is kept in
`agent.log`, and Codex's final response is kept in `agent-summary.md`.

The Jetson runs Ubuntu 24.04 with Bubblewrap installed but without the optional
`bwrap-userns-restrict` AppArmor profile. A default Codex command sandbox can
therefore fail while configuring its private loopback interface. The adapter
keeps the `workspace-write` filesystem boundary and enables command-network
access, avoiding that network-namespace operation without granting
`danger-full-access`. This follows the narrower-boundary guidance in the
[official OpenAI sandbox documentation](https://developers.openai.com/codex/sandboxing).
If host policy later supplies the reviewed AppArmor profile, remove this
compatibility override and re-run the M4 interruption and write-boundary tests.

The detached adapter waits at most two hours for archival and owns Codex through
a dedicated process group with a 30-minute runtime bound. Timeout or an
explicit stop terminates that group and atomically changes `agent-run.json` to
`failed`; an interrupted agent must never remain `running`. A deliberate
agent-authored `waiting-for-human` result is preserved rather than overwritten
with `completed`. Stop one exact run with:

```sh
./scripts/quattro-agent-adapter.sh --run-id RUN_ID --stop
```

This is an explicit, bounded coding-agent workflow—not general provider
launching. It cannot hand off the VT, stop or restore GDM, alter
`/home/looco/omarchy`, install packages, or change JetPack/NVIDIA state. The
Quickshell container receives only sanitized action state; provider credentials
remain on the host.
