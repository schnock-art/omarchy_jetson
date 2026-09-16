# Agent integration

Quattro’s agent experience is coupled to the Omarchy command and desktop environment, but the useful conceptual pieces are portable: a provider/default-agent abstraction, process launching, environment/context handoff, skills, approval modes, monitoring, and shell-visible controls.

For the Workshop, preserve a distinction between participants and the operating environment. Aster, Codex, Nemotron, humans, and future agents should be peers using shared interfaces—not one model embedded as the OS.

Initial porting should isolate provider launchers and IPC from Arch package management. Do not enable autonomous/background agents during reconnaissance. Jetson CUDA/TensorRT/local inference should remain a separate capability service until the desktop shell boundary is proven.
