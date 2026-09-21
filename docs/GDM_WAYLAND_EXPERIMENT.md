# Reversible GDM Wayland feasibility experiment

## Scope

This experiment answers one question: can this Jetson enable GDM Wayland while
preserving both the normal Ubuntu Wayland and Ubuntu Xorg login paths?

It does not install Quattro, create a Quattro session entry, enable automatic
login, change the preferred/default session, stop GDM permanently, or modify
the NVIDIA/JetPack stack. The experiment must end by restoring the exact
original GDM configuration even when the result passes.

The prepared experiment is:

```text
ID:                20260922-090045
Original SHA-256:  a497ef003bdaafb86f23ab304f13eac8f2565d629acbfd64babac1f22a840a5a
Candidate SHA-256: e887bf9330b99dd818d64eb49f352a2105d3e3f9a49860e6ca6640a037d2285d
State:             prepared
```

The sole candidate change is:

```diff
-WaylandEnable=false
+WaylandEnable=true
```

The original and candidate files, manifest, and baseline probe are retained in
`artifacts/gdm-wayland-experiments/20260922-090045/`.

## Safety prerequisites

Before applying anything:

1. Keep a working SSH login open from a second computer.
2. Confirm the Jetson is physically accessible and a local text VT works.
3. Do not run apply/restart from a terminal inside the graphical desktop; the
   GDM restart will end that session.
4. Copy the rollback command below to the SSH terminal before restarting GDM.
5. Do not continue if the experiment status reports `external`, a changed hash,
   an inactive GDM service, or any state other than `prepared`.

Read-only check:

```sh
cd /home/looco/repos/omarchy_jetson
ID=20260922-090045
./scripts/quattro-gdm-wayland-experiment.py status --experiment-id "$ID"
```

## Apply and restart

From the physical text VT or the already-tested SSH recovery connection:

```sh
cd /home/looco/repos/omarchy_jetson
ID=20260922-090045
./scripts/quattro-gdm-wayland-experiment.py apply \
  --experiment-id "$ID" --approve --ssh-recovery-confirmed
./scripts/quattro-gdm-wayland-experiment.py restart \
  --experiment-id "$ID" --approve --ssh-recovery-confirmed
```

`apply` validates the original and candidate hashes, writes only
`/etc/gdm3/custom.conf`, and verifies the installed candidate hash. `restart`
is a separate operation so an operator can inspect or roll back before GDM is
affected. Both operations reject an ordinary graphical pseudo-terminal.

If the login screen is blank, corrupted, or unavailable, stop the experiment
and run the rollback command over SSH immediately.

## Verify both normal Ubuntu paths

At GDM, first choose **Ubuntu on Wayland** explicitly and log in. Do not rely on
a remembered session choice. From a terminal in that desktop:

```sh
cd /home/looco/repos/omarchy_jetson
ID=20260922-090045
./scripts/quattro-gdm-wayland-experiment.py verify \
  --experiment-id "$ID" --expect wayland
```

Confirm the desktop renders, keyboard/mouse work, and NVIDIA/CUDA remain
available. Log out normally. Then choose **Ubuntu on Xorg** explicitly, log in,
and run:

```sh
./scripts/quattro-gdm-wayland-experiment.py verify \
  --experiment-id "$ID" --expect x11
```

Confirm the same basic desktop, input, and NVIDIA behavior. Missing session
choices, a probe mismatch, visual corruption, or inability to return to GDM is
a failed experiment and requires rollback.

## Mandatory rollback

From SSH or a physical text VT, restore the byte-for-byte original file and
restart GDM:

```sh
cd /home/looco/repos/omarchy_jetson
ID=20260922-090045
./scripts/quattro-gdm-wayland-experiment.py rollback \
  --experiment-id "$ID" --approve --restart-gdm
```

Rollback refuses to overwrite an externally modified GDM file. It accepts only
the exact original or experiment candidate hash. After rollback:

```sh
./scripts/quattro-gdm-wayland-experiment.py status --experiment-id "$ID"
sha256sum /etc/gdm3/custom.conf
systemctl is-active gdm3
```

The status must report `rolled-back`, `installedVersion: before`, and active
GDM. The installed checksum must be
`a497ef003bdaafb86f23ab304f13eac8f2565d629acbfd64babac1f22a840a5a`.
Finally, log into the ordinary Ubuntu Xorg session once more.

## Acceptance

The experiment passes only when:

- the Wayland session is offered and reports session type `wayland`;
- the Xorg session remains offered and reports session type `x11`;
- both render and accept keyboard/mouse input;
- GDM returns after both logouts;
- NVIDIA and CUDA remain healthy;
- the exact original GDM configuration is restored; and
- a final Ubuntu Xorg login succeeds after rollback.

A pass authorizes design of the S3 narrow service; it does not authorize a
Quattro session installation or a default-session change.
