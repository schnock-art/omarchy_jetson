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
