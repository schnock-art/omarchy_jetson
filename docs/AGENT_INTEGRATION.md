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
