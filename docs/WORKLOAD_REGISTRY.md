# Jetson lab workload registry

The workload panel is a read-only view of explicitly registered lab jobs. Its
state lives in the local ignored path `artifacts/workloads/registry.json` and
is mounted read-only into the Quattro sidecar. The panel cannot execute,
terminate, or alter jobs.

Initialize or inspect the registry over SSH:

```sh
cd /home/looco/repos/omarchy_jetson
./scripts/quattro-workloads.sh init
./scripts/quattro-workloads.sh list
```

For a safe end-to-end demonstration, run the built-in harmless sample. It
sleeps for 15 seconds, writes a small log, and marks itself complete:

```sh
./scripts/quattro-workloads.sh sample
```

The workload panel shows up to three recent jobs with name, state, owner,
start time, and host log path. Generic shell execution and process-killing
controls are intentionally out of scope.
