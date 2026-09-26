#!/usr/bin/env python3
"""Collect a fixed, read-only L0 host inventory for the local-builder design."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import shutil
import socket
import subprocess
import tempfile
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(command: list[str], timeout: float = 10) -> dict[str, Any]:
    executable = shutil.which(command[0])
    if executable is None:
        return {"command": command, "available": False, "returnCode": None, "stdout": "", "stderr": ""}
    try:
        completed = subprocess.run(
            [executable, *command[1:]],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "command": command,
            "available": True,
            "returnCode": completed.returncode,
            "stdout": completed.stdout.rstrip(),
            "stderr": completed.stderr.rstrip(),
        }
    except subprocess.TimeoutExpired as error:
        return {
            "command": command,
            "available": True,
            "returnCode": None,
            "timedOut": True,
            "stdout": (error.stdout or "").rstrip() if isinstance(error.stdout, str) else "",
            "stderr": (error.stderr or "").rstrip() if isinstance(error.stderr, str) else "",
        }


def read(path: str) -> str | None:
    try:
        return pathlib.Path(path).read_text(encoding="utf-8").rstrip()
    except (OSError, UnicodeError):
        return None


def path_state(path: str) -> dict[str, Any]:
    item = pathlib.Path(path)
    state: dict[str, Any] = {"path": path, "exists": item.exists()}
    if item.exists():
        info = item.stat()
        state.update(
            mode=oct(info.st_mode & 0o7777),
            uid=info.st_uid,
            gid=info.st_gid,
            readable=os.access(item, os.R_OK),
            writable=os.access(item, os.W_OK),
        )
    return state


def matching_output(result: dict[str, Any], needles: tuple[str, ...]) -> dict[str, Any]:
    result = dict(result)
    result["stdout"] = "\n".join(
        line for line in result.get("stdout", "").splitlines() if any(needle in line for needle in needles)
    )
    return result


def atomic_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as output:
            json.dump(value, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise


def collect() -> dict[str, Any]:
    mount_targets = ["/", "/home", "/tmp", "/run", str(ROOT), str(ROOT.parent)]
    sysctls = [
        "/proc/sys/kernel/unprivileged_userns_clone",
        "/proc/sys/user/max_user_namespaces",
        "/proc/sys/kernel/apparmor_restrict_unprivileged_userns",
        "/proc/sys/kernel/unprivileged_bpf_disabled",
        "/proc/sys/kernel/yama/ptrace_scope",
    ]
    commands = {
        "freeBytes": run(["free", "--bytes"]),
        "swap": run(["swapon", "--show", "--bytes"]),
        "diskFree": run(["df", "--block-size=1", "--output=source,fstype,size,used,avail,pcent,target", "/", "/home", "/tmp", "/run"]),
        "blockDevices": run(["lsblk", "--json", "--bytes", "--output", "NAME,PATH,SIZE,FSTYPE,MOUNTPOINTS"]),
        "mounts": [run(["findmnt", "--json", "--target", target]) for target in mount_targets],
        "powerMode": run(["nvpmodel", "-q"]),
        "tegrastats": run(["timeout", "2.2", "stdbuf", "-oL", "tegrastats", "--interval", "1000"], timeout=4),
        "nvidiaSmi": run(["nvidia-smi"]),
        "cudaCompiler": run(["nvcc", "--version"]),
        "cudaLibraries": matching_output(run(["ldconfig", "-p"]), ("libcuda.so", "libnvinfer.so")),
        "ollamaVersion": run(["ollama", "--version"]),
        "ollamaSystemEnabled": run(["systemctl", "is-enabled", "ollama.service"]),
        "ollamaSystemActive": run(["systemctl", "is-active", "ollama.service"]),
        "ollamaUserEnabled": run(["systemctl", "--user", "is-enabled", "ollama.service"]),
        "ollamaUserActive": run(["systemctl", "--user", "is-active", "ollama.service"]),
        "listeners": run(["ss", "-ltn"]),
        "bubblewrapVersion": run(["bwrap", "--version"]),
        "apparmorService": run(["systemctl", "show", "apparmor.service", "-p", "ActiveState", "-p", "SubState", "-p", "UnitFileState"]),
        "apparmorStatus": run(["aa-status"]),
        "systemdVersion": run(["systemd", "--version"]),
        "userManager": run(["systemctl", "--user", "show", "-p", "ControlGroup", "-p", "Delegate", "-p", "TasksMax"]),
        "gitVersion": run(["git", "--version"]),
        "gitRevision": run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
        "gitStatus": run(["git", "-C", str(ROOT), "status", "--porcelain=v1"]),
        "gitWorktrees": run(["git", "-C", str(ROOT), "worktree", "list", "--porcelain"]),
        "identity": run(["id"]),
    }
    tools = [
        "bwrap", "unshare", "setpriv", "systemd-run", "aa-status", "apparmor_parser",
        "git", "newuidmap", "newgidmap", "slirp4netns", "prlimit", "timeout", "sudo",
    ]
    return {
        "schemaVersion": 1,
        "kind": "local-builder-l0-host-inventory",
        "collectedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "hostname": socket.gethostname(),
        "root": str(ROOT),
        "kernel": read("/proc/sys/kernel/osrelease"),
        "osRelease": read("/etc/os-release"),
        "meminfo": read("/proc/meminfo"),
        "procSwaps": read("/proc/swaps"),
        "lsm": read("/sys/kernel/security/lsm"),
        "apparmorContext": read("/proc/self/attr/current"),
        "cgroup": read("/proc/self/cgroup"),
        "cgroupFilesystem": run(["stat", "-fc", "%T", "/sys/fs/cgroup"]),
        "sysctls": {path: read(path) for path in sysctls},
        "tools": {tool: shutil.which(tool) for tool in tools},
        "paths": [path_state("/run/docker.sock"), path_state("/var/run/docker.sock")],
        "commands": commands,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, help="atomically write the JSON inventory")
    arguments = parser.parse_args()
    inventory = collect()
    if arguments.output:
        atomic_json(arguments.output.resolve(), inventory)
    else:
        print(json.dumps(inventory, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
