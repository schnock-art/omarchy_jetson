# MVP maintenance baseline

## Known-good evidence and dependencies

The accepted physical run is retained locally at
`artifacts/quattro-runs/20260922-063507-9503/`. Its deterministic result passes
all required checks, including the human-recorded visual assertions and GDM
restoration.

The run and build inputs are:

| Item | Recorded value |
| --- | --- |
| Accepted run | `20260922-063507-9503` |
| Run's base repository revision | `9e0533e3e9186586e5441c641617f31351aeecc8` |
| Run worktree | Dirty; the MVP implementation was not yet committed |
| Upstream `/home/looco/omarchy` revision | `2fbac0c8e88eca704af1650ce721a494bd11a3d0` |
| `hyprland:phase2-runtime` image | `sha256:efa5c055c72a0856dc0116b4fba87ec40d5cba2d19903f35300d3c68d9c14ed9` |
| `quickshell:phase1-hypr-lab` image | `sha256:17a2f09804d6b4ae883249bed30f8caab9d6beaa9b22a30fecd57a40a41e4135` |
| Acceptance manifest SHA-256 | `98e0c1c6abcf1b1c9754502986eaab2ee44dbf0b0acf35c0b10a1329f83aac9d` |
| Committed MVP implementation | `583d3280b36b9067b9d79036f347efffee74a92b` |

The base revision alone does not reconstruct the accepted run because its
worktree was dirty. The committed MVP implementation is the reproducible source
baseline created from that accepted tree; do not rewrite the archived run's
revision to match the later commit.

## Supported operator commands

The complete current workflow is in [STARTUP_WORKFLOW.md](STARTUP_WORKFLOW.md).
The shortest operational reference is:

```sh
# Physical local VT: validate and start
cd /home/looco/repos/omarchy_jetson
./scripts/check-syntax.sh
./scripts/start-quattro-lab.sh

# SSH or normal desktop: inspect
./scripts/quattro-health-report.sh --host
./scripts/quattro-health-report.sh --latest
./scripts/quattro-mvp.py status --run-id RUN_ID

# Stop one exact adapter
./scripts/quattro-agent-adapter.sh --run-id RUN_ID --stop
```

Use `Super+Shift+E` for normal exit. If a display attempt fails, restore GDM
before diagnosing or changing code:

```sh
sudo systemctl start gdm3
sudo docker ps -a --filter name=hyprland-phase2-drm \
  --filter name=quickshell-quattro-smoke
```

Do not delete stopped containers until their logs and inspection records have
been archived. The next supported launcher invocation performs that recovery.

## Schema compatibility policy

The MVP uses versioned JSON at trust boundaries. Schema version `1` is the only
accepted major version today.

- Readers must reject unknown major versions and malformed required fields.
- Writers may add optional fields within version `1` only when old readers can
  safely ignore them and their existing meanings do not change.
- Renaming a field, changing its type or meaning, weakening validation, or
  adding a new state/action that old policy could misinterpret requires a new
  schema version and fixtures for both rejection and migration behavior.
- Persisted records are written to a temporary file and atomically renamed.
- Archived evaluation reads only the selected bundle. It must not follow
  symlinks or recover data from `/tmp`, a live mount, or retained Docker state.
- Historical archives are immutable. Compatibility fixes belong in readers or
  an explicit derived report, never by editing old evidence.

The canonical acceptance requirements live in `mvp/acceptance.json`. Reports,
agents, and tests must consume that contract rather than duplicate its milestone
or fatal-pattern lists.

## Adding an allowlisted action

1. Define a stable, versioned action identifier and its exact input shape.
2. Add a fixed dispatch mapping in `scripts/quattro-action-gateway.sh`. Never
   execute a command or arguments supplied by the request record.
3. Bound runtime, validate the request ID and schema, suppress duplicates, and
   produce exactly one terminal correlated result.
4. Expose only the smallest sanitized state required by QML. Keep parsing,
   collection, policy, and host mutation out of the panel.
5. Add normal, malformed, unknown-version, duplicate, timeout, interruption,
   and gateway-shutdown fixtures.
6. Run `scripts/check-syntax.sh`; bundle any rendering change into one planned
   human visual checkpoint.

An action which needs arbitrary arguments, shell text, a writable host home,
Docker access, or unrestricted D-Bus is not eligible for this protocol.

## Adding an agent provider

1. Keep the provider implementation in the host agent plane and rooted at this
   repository. Credentials must never enter the Quickshell container.
2. Preserve the adapter contract: explicit approval, one run ID, one ownership
   lock, bounded pre-archive wait, bounded execution, process-group cleanup,
   atomic state, sanitized UI status, and a per-run stop path.
3. Translate provider output into the existing terminal states:
   `completed`, `waiting-for-human`, or `failed`. A provider must not determine
   visual success.
4. Give the provider the fixed acceptance objective and safety constraints; do
   not accept arbitrary QML prompts.
5. Add fixtures for unavailable/auth failure, timeout, interruption, stop,
   malformed output, human gate, and deterministic-evaluator disagreement.
6. Document executable discovery and sandbox assumptions in
   [AGENT_INTEGRATION.md](AGENT_INTEGRATION.md).

Provider output is advisory. `scripts/quattro-mvp.py` and the archived contract
remain the authority for PASS/FAIL.

## Maintenance checks

After shell, QML, manifest, or runtime configuration changes:

```sh
./scripts/check-syntax.sh
./tests/mvp/test-conductor.sh
git diff --check
```

Physical testing remains mandatory for rendering, layout, input, compositor
lifecycle, or a host/container display-boundary change. Record facts proven by
automation separately from human visual observations.
