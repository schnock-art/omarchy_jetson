# Jetson lab workload registry

The workload panel is a view of explicitly registered lab jobs. Its state
lives in the local ignored path `artifacts/workloads/registry.json` and is
mounted read-only into the Quattro sidecar. During a physical Quattro session,
the panel may submit one separately confirmed action: the fixed harmless sample
job described below. It cannot execute arbitrary commands, pass arguments,
terminate jobs, or access credentials.

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
start time, and host log path. Its **Start harmless sample…** button needs a
second explicit confirmation, sends a fixed request to a short-lived host
gateway, and does nothing while another harmless sample is running. The gateway
exists only for that Quattro session and accepts no other request value.

Generic shell execution, process killing, provider launch, networked agent
actions, and privileged operations are intentionally out of scope.
