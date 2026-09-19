# Jetson telemetry panel

The Quattro lab session now carries a small `󰍛` panel immediately before PWR.
It is a read-only display of the Jetson's current `tegrastats` sample:

- average online CPU utilization and GR3D (GPU) utilization;
- RAM used / total;
- junction and GPU temperatures;
- `VIN_SYS_5V0` input power; and
- the active `nvpmodel` label, such as `NV Power Mode: MODE_30W`.

While the panel is open it also retains the last 60 one-second samples in
memory. The chart draws CPU and GPU utilization, and the panel reports CPU,
GPU, and junction-temperature peaks for that short window. This history exists
only in the running Quickshell process and disappears when the lab session
ends; it does not create a host telemetry database.

## Runtime boundary

`scripts/collect-jetson-telemetry.sh` runs on the host as `looco`, using the
host's existing `tegrastats` and `nvpmodel` commands. It writes one atomically
replaced JSON file in a temporary directory. The Quattro sidecar receives only
a read-only mount of that directory at `/tmp/jetson-telemetry`; it has no
access to the underlying telemetry devices and cannot alter the power mode.

The launcher starts the collector only for `--quattro`, verifies the first
sample before stopping GDM, and stops it when the test ends. As with the other
lab-side temporary diagnostics, its directory is retained under
`/tmp/jetson-telemetry.*` if post-run inspection is useful.

## Physical test

From a local text console on the Jetson, use the normal lab command:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/start-quattro-lab.sh
```

Once the bar is visible, click the new chip/GPU icon (`󰍛`) just to the left of
PWR. The panel should populate within a second and values should refresh while
it remains open. Exit with `Super+Shift+E`; GDM should return as usual.

For an independent host-only collector check (safe over SSH):

```sh
out=$(mktemp -d /tmp/telemetry-check.XXXXXX)
(timeout 5 /home/looco/repos/omarchy_jetson/scripts/collect-jetson-telemetry.sh "$out/telemetry.json") &
collector=$!
sleep 3
jq . "$out/telemetry.json"
wait "$collector" || true
```
