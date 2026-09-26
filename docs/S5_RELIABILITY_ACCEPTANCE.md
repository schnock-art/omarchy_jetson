# S5 reliability and reboot acceptance

## Purpose and status

S4 proves that an explicitly selected **Quattro (Jetson preview)** GDM session
can run once and return safely to GDM. S5 proves that it remains recoverable
across normal use, bounded failures, and a reboot before any daily-use local
inference or repository-builder capability is trusted.

Status: **S5-0 through S5-5 are physically verified; the S5 reliability gate
is complete.** No S5 scenario is
accepted until all of its automated evidence and required human observations
are retained. This document does not authorize a default session, automatic
login, boot-time Quattro, or a permanent GDM Wayland policy change.

The S3 unit remains deliberately static, but S5-0 now adds and fixture-tests a
narrowly scoped, boot-available **socket activation** path. The socket may
listen for the fixed control protocol, but it must not start Quattro, select a
GDM session, or enable the service itself at boot.

## Preconditions

### Repeated-login investigation (2026-09-23)

Runs `20260923-223737-146741`, `20260923-223821-148856`, and
`20260923-223923-151077` failed with Hyprland exit 134. Their archived Docker
records expose only the assigned tty2 plus tty0; seatd logs explicitly attempt
VT 1 and fail before acquiring devices. This establishes a foreground/assigned
VT mismatch, not evidence that stale containers caused the failures.

The runtime now requires three consecutive matching foreground/logind samples
immediately before compositor launch, with a bounded ten-attempt wait. Run
`20260924-081856-26426` retained three matching tty2 samples and still failed:
seatd independently tried to allocate VT 1. This disproves a host foreground
race as the sufficient cause. The GDM runtime therefore sets
an unbound seatd instance, the seatd-supported mode that disables its VT
allocation; GDM/logind retains VT lifecycle ownership and the host-side checks
still fail closed before launch. Run `20260924-083308-52099` proved that merely
passing `SEATD_VTBOUND=0` into the container is ineffective: seatd-launch 0.9.2
starts seatd with an empty environment, and the daemon again attempted VT 1.
The runtime image now uses a bounded direct seatd bootstrap for `gdm-session`
so the daemon itself receives `SEATD_VTBOUND=0`. The physical `lab-vt` backend
keeps its existing VT-bound seatd-launch behavior.

Failure enters the existing archive/cleanup path; both `seat-check.jsonl` and
`supervisor.log` are retained. Fixtures cover delayed readiness, repeated
invocation, wrong foreground, unavailable sysfs, malformed logind output, and
vanished sessions. The change requires physical verification and is not a
claim that S5 passes. Do not expose the greeter's tty1 to make the error vanish.

Experiment `20260923-204805` is verified rolled back to its original hash with
GDM active. Experiment `20260924-083032` remains the failed candidate until its
explicit rollback is recorded. Rebuild the runtime image and refresh the
reviewed service bundle before a new experiment; then collect two consecutive
physical cycles and their new seat records. Historical archives are unchanged.
The older `revision: unavailable` records remain an unresolved metadata defect;
the previous explanation about an old runtime was not established by evidence.

### Login-bounce regression result (2026-09-24)

Run `20260924-084627-72501` authenticated successfully, but the installed S4
wrapper still used its original 15-second response timeout. The fixed service
needed about 16 seconds to publish readiness, so the wrapper timed out first,
GDM closed the session, and startup completed after its owning logind session
had disappeared. The exact labelled run was subsequently archived with exit
143 and its two owned containers were removed.

The checkout already used a 60-second response bound, but the S4 installer had
no source-freshness signal or transactional refresh operation. The entry status
now reports `filesMatchSource`, idempotent install rejects a stale protected
bundle with an explicit refresh instruction, and `refresh --approve` replaces
only the two reviewed S4 files with rollback on failure. Its active-run guard
fails closed, while accepting a stale control record only when the matching
runtime record is terminal and its archive is complete.

After the installed wrapper was refreshed, the human completed two successful
Quattro login/logout cycles:

| Run | Automated archive facts | Human observation |
| --- | --- | --- |
| `20260924-105055-189127` | Exit `0`; three stable `tty2` seat samples; Hyprland/seatd ran for about 123 seconds and shut down normally | Quattro login succeeded and returned cleanly |
| `20260924-105337-197726` | Exit `0`; three stable `tty2` seat samples; Hyprland/seatd ran for about 88 seconds and shut down normally | A second consecutive Quattro login succeeded and returned cleanly |

This is retained physical evidence for the login-bounce fix and consecutive
start cleanup. The runs remain `awaiting-visual-check`: the operator reported
successful logins, not the complete S5-1 shell/input/audio/panels/actions
checklist. Do not rewrite them as passing acceptance runs.

Regression fixtures now bind the wrapper response timeout directly to the
service's `START_TIMEOUT` with delivery headroom, detect installed files that
match an old protected record but not current reviewed sources, require an
explicit refresh, cover active/stale-terminal run handling, and prove rollback
restores the prior entry bundle and state after a partial refresh failure.

1. Work from the committed/reviewed repository state and keep a separate SSH
   recovery connection open.
2. Run the required syntax gate:

   ```sh
   cd /home/looco/repos/omarchy_jetson
   ./scripts/check-syntax.sh
   ```

   When the runtime entrypoint changed, rebuild the fixed image before testing:

   ```sh
   sudo docker build -t hyprland:phase2-runtime containers/hyprland-runtime
   sudo ./scripts/quattro-gdm-session-install.py refresh --approve
   ```

3. Confirm the root-owned session service is active but static, and the entry
   matches the reviewed source. Until S5-0 is implemented, this only proves the
   pre-reboot checkpoint; it does not prove that a GDM selection can activate
   the service after a reboot:

   ```sh
   sudo ./scripts/quattro-gdm-session-install.py status
   sudo ./scripts/quattro-gdm-session-entry.py status
   systemctl is-active gdm3
   ```

   The service must be active and not enabled at boot. Do not proceed if the
   installer reports changed files, an unsafe socket, or a changed GDM record.

4. Prepare a **new** reversible GDM Wayland experiment bundle. Never reuse or
   rewrite the historical S2/S4 experiment evidence:

   ```sh
   EXPERIMENT_ID=$(date +%Y%m%d-%H%M%S)
   ./scripts/quattro-gdm-wayland-experiment.py prepare \
     --experiment-id "$EXPERIMENT_ID"
   ```

5. From a physical VT or the already-tested SSH recovery channel, apply and
   restart only that fresh experiment:

   ```sh
   ./scripts/quattro-gdm-wayland-experiment.py apply \
     --experiment-id "$EXPERIMENT_ID" --approve --ssh-recovery-confirmed
   ./scripts/quattro-gdm-wayland-experiment.py restart \
     --experiment-id "$EXPERIMENT_ID" --approve --ssh-recovery-confirmed
   ```

Keep `EXPERIMENT_ID` and every resulting Quattro run ID in the scenario notes.

## Scenario matrix

Run the scenarios in order. Stop after a failed safety assertion, preserve the
run/service logs, restore GDM, and record the failure; do not improvise a
partial lifecycle sequence.

| ID | Scenario | Automated evidence | Human observation | Pass condition |
| --- | --- | --- | --- | --- |
| S5-0 | Socket-activation design and fixture gate | Installer, static-service, socket ownership, malformed-peer, and boot-state fixtures | None | **Implemented; fixture suite passes.** Host install/rollback and physical reboot evidence remain pending. |
| S5-1 | Two consecutive normal Quattro logins/logouts | One complete archive per run; stored acceptance result; service remains active | Shell, input, audio, panels, fixed actions, and `Super+Shift+E` work each time | Both runs return to GDM and the second start is not blocked by the first. |
| S5-2 | Controlled failed start | Exact service/runtime logs and terminal archive state | GDM remains usable; no blank/stuck replacement desktop | Failure is bounded, no stale run/container prevents a new selection, and an Ubuntu Xorg login works. |
| S5-3 | Controlled compositor/session termination | Terminal session record and archive after the bounded failure | GDM returns or is recoverable through the documented SSH command | No stale session/container remains; a later Quattro normal login and Ubuntu Xorg login work. |
| S5-4 | Reboot recovery | Fresh post-reboot baseline verification and service/entry status | GDM appears; Ubuntu Xorg and one explicit Quattro selection work | The fixed service can activate through its socket, no Quattro autostart occurs, and the session can still exit to GDM. |
| S5-5 | Final rollback | GDM experiment status and original configuration checksum | Ubuntu Xorg renders and accepts input after rollback | Exact original GDM policy is restored and GDM is active. |

### S5-1 result (2026-09-26)

Runs `20260926-174258-30021` and `20260926-175238-56331` each have a passing
20-check stored acceptance result, completed bounded archive review, explicit
human confirmation of the full S5-1 visual checklist, and normal exit to GDM.
The second completed after the first, proving no retained container or session
blocked the consecutive start. S5-1 is physically verified.

S5-2 and S5-3 require a reviewed failure trigger before execution. Do not kill
arbitrary system processes, Docker resources, GDM, or user sessions to invent a
failure. If a trigger is not yet implemented, record these as pending rather
than treating normal logout as a failure test.

S5-2 now has a fixed one-shot trigger at
`/run/omarchy-quattro/s5-failure-once.json`. It accepts only a root-owned,
mode-0600 `preflight-v1` record, is consumed into that run before containers
start, and is archived as `failure-injection.json`; it is never exposed to QML
or session requests. Arm it immediately before the physical S5-2 selection:

```sh
sudo ./scripts/quattro-s5-failure-trigger.sh arm --approve
```

The selected Quattro session must fail back to GDM without starting containers.
After preserving the resulting run, verify that the trigger is consumed with
`sudo ./scripts/quattro-s5-failure-trigger.sh status`.

### S5-2 result (2026-09-26)

Run `20260926-195239-143484` consumed the armed `preflight-v1` record and
failed with exit `2` before either Quattro container started. Its archive
contains both `failure-injection.json` and the exact supervisor message
`S5 controlled preflight failure requested`. The trigger subsequently reported
`armed: false`; GDM and the socket listener were active, and no fixed Quattro
container remained. The human confirmed the expected prompt return to GDM.
S5-2 is physically verified.

The first armed attempt exposed an arming-utility defect: it changed the shared
socket directory to mode `0700`, causing the wrapper to fail with socket
permission denied before the runtime could consume the trigger. The utility now
preserves the socket directory at `0755`, while the trigger file stays mode
`0600`; a fixture protects that boundary.

For S5-3, arm the separate post-ready termination trigger only after refreshing
the reviewed service bundle:

```sh
sudo ./scripts/quattro-s5-termination-trigger.sh arm --approve
```

It is consumed only after both fixed containers are running and the runtime has
published `ready`; it stops only the labelled Hyprland container, archives
`termination-injection.json`, and uses the normal cleanup path. Select Quattro
locally, observe the prompt return to GDM, then verify the trigger reports
`armed: false`. Do not use this to terminate any unrelated process or session.

### S5-3 result (2026-09-26)

Run `20260926-200144-158633` reached `ready`, consumed the armed
`terminate-after-ready-v1` record, and archived it as
`termination-injection.json`. It then exited with code `2` and the exact
supervisor message `S5 controlled post-ready termination requested`; the
trigger subsequently reported `armed: false`. The human observed the expected
return to GDM. A subsequent normal Quattro selection succeeded in run
`20260926-200214-160687`, and the human then confirmed that an Ubuntu Xorg
login worked normally. S5-3 is physically verified.

### S5-4 result (2026-09-26)

Baseline `artifacts/reboot-baselines/20260926-201113.json` matched after an
ordinary Ubuntu reboot: GDM, Docker, the desktop user bus, PipeWire, the
kernel, and both retained runtime images all passed. The installed session
bundle still matched source, the service remained static (`enabledAtBoot:
false`), and only its fixed socket was boot-enabled. A read-only managed
container listing was empty before the explicit selection, proving Quattro did
not auto-start. The human confirmed Ubuntu Xorg worked after reboot, then
selected Quattro for run `20260926-201643-177220`; it exited cleanly, its
archived health report passed 10 checks with no warnings or failures, and the
human confirmed `Super+Shift+E` returned to GDM. S5-4 is physically verified.

### S5-5 result (2026-09-26)

The approved GDM experiment `20260924-084355` was rolled back from its exact
candidate hash to its exact original hash
`a497ef003bdaafb86f23ab304f13eac8f2565d629acbfd64babac1f22a840a5a`.
Its status reports `state: rolled-back`, `installedVersion: before`, and active
GDM; the direct checksum matched the recorded original. The human confirmed an
Ubuntu Xorg login worked after the GDM restart. S5-5 is physically verified,
and the complete S5 reliability gate is accepted.

## Per-run procedure

At GDM explicitly select **Quattro (Jetson preview)**. For each normal run,
exercise the same accepted visual checkpoint: shell rendering, keyboard,
pointer, audio, Agents/telemetry/workloads panels, fixed actions, and normal
exit with `Super+Shift+E`.

After GDM returns, over SSH record the archived facts without relying on live
container state:

```sh
cd /home/looco/repos/omarchy_jetson
RUN_ID=the-run-id-created-by-the-session
./scripts/quattro-mvp.py evaluate --run-id "$RUN_ID"
./scripts/quattro-health-report.sh --run "$RUN_ID"
sudo ./scripts/quattro-gdm-session-install.py status
sudo ./scripts/quattro-gdm-session-entry.py status
systemctl is-active gdm3
```

Record the human visual assertions with the established MVP command only when
they were actually observed. A successful log or evaluator cannot supply that
assertion.

## Reboot procedure

Before reboot, capture a read-only baseline:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-reboot-check.sh --capture
```

Reboot through the ordinary Ubuntu mechanism. After the host returns, log in
to Ubuntu Xorg first and verify the captured baseline from that normal session:

```sh
./scripts/quattro-reboot-check.sh --verify artifacts/reboot-baselines/BASELINE.json
sudo ./scripts/quattro-gdm-session-install.py status
sudo ./scripts/quattro-gdm-session-entry.py status
```

After S5-0, the socket (not the service) may be boot-available and activate the
fixed service on the first validated client connection. The service itself must
still not report enabled at boot, Quattro must not have launched automatically,
and the socket must not accept a generic command. Then run S5-4's single
explicit Quattro selection and normal exit.

## Mandatory rollback and recovery

Once all temporary Wayland tests are complete—or immediately after a failure—
restore the fresh experiment bundle's original GDM policy:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-gdm-wayland-experiment.py rollback \
  --experiment-id "$EXPERIMENT_ID" --approve --restart-gdm
./scripts/quattro-gdm-wayland-experiment.py status --experiment-id "$EXPERIMENT_ID"
systemctl is-active gdm3
```

If GDM is not visible, use SSH first:

```sh
sudo systemctl start gdm3
systemctl is-active gdm3
```

Preserve run archives and experiment bundles. Do not delete stopped labelled
containers before the documented archival/recovery path has captured them.

## Acceptance record

S5 is physically verified only when the repository retains:

- a scenario ledger mapping S5-1 through S5-5 to run IDs/experiment ID;
- evaluator and health-report output for each applicable run;
- explicit human observations for each display/input assertion;
- installer/entry state proving no boot enablement and unchanged default
  session policy;
- a post-reboot baseline comparison;
- the original GDM configuration checksum after rollback; and
- an ordinary Ubuntu Xorg login after every failure/recovery class.

When S5 is accepted, update `SESSION_INTEGRATION_PLAN.md`, `README.md`, and
the historical-result document with the evidence. Only then may L1 of
[LOCAL_BUILDER_PLAN.md](LOCAL_BUILDER_PLAN.md) install and benchmark Ollama.
