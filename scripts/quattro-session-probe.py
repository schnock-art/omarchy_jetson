#!/usr/bin/env python3
"""Read-only GDM/logind session capability probe for Quattro."""

from __future__ import annotations

import argparse
import configparser
import datetime as dt
import glob
import json
import os
import pathlib
import pwd
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any


SCHEMA_VERSION = 1
ROOT = pathlib.Path(__file__).resolve().parent.parent
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")
SESSION_PROPERTIES = (
    "Id", "User", "Name", "Active", "State", "Remote", "Type", "Class",
    "Seat", "TTY", "VTNr", "Leader", "Scope", "Service", "Desktop", "Display",
)


class ProbeError(RuntimeError):
    pass


def run(command: list[str], timeout: int = 5) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(command, 124, "", str(exc))


def parse_properties(raw: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in raw.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def session_properties(session_id: str) -> dict[str, str]:
    if not SESSION_ID_RE.fullmatch(session_id):
        raise ProbeError(f"invalid session ID: {session_id!r}")
    result = run(["loginctl", "show-session", session_id, *sum((["-p", key] for key in SESSION_PROPERTIES), [])])
    if result.returncode != 0:
        raise ProbeError(f"cannot inspect logind session {session_id}: {result.stderr.strip()}")
    values = parse_properties(result.stdout)
    if values.get("Id") not in (None, "", session_id):
        raise ProbeError("logind returned a different session")
    return values


def resolve_session(requested: str, uid: int) -> tuple[str, dict[str, str]]:
    candidates: list[str] = []
    if requested != "auto":
        candidates.append(requested)
    else:
        if os.environ.get("XDG_SESSION_ID"):
            candidates.append(os.environ["XDG_SESSION_ID"])
        display = run(["loginctl", "show-user", str(uid), "-p", "Display", "--value"])
        if display.returncode == 0 and display.stdout.strip():
            candidates.append(display.stdout.strip())
    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        try:
            values = session_properties(candidate)
        except ProbeError:
            if requested != "auto":
                raise
            continue
        if values.get("User") == str(uid):
            return candidate, values
        if requested != "auto":
            raise ProbeError(f"session {candidate} does not belong to uid {uid}")
    raise ProbeError("could not resolve the current user's GDM/logind display session")


def mode_string(mode: int) -> str:
    return oct(stat.S_IMODE(mode))[2:].zfill(3)


def acl_for(path: pathlib.Path, username: str) -> str | None:
    result = run(["getfacl", "-cp", str(path)])
    if result.returncode != 0:
        return None
    prefix = f"user:{username}:"
    for line in result.stdout.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):]
    return None


def device_record(path: pathlib.Path, kind: str, username: str) -> dict[str, Any]:
    info = path.stat()
    return {
        "path": str(path),
        "kind": kind,
        "characterDevice": stat.S_ISCHR(info.st_mode),
        "ownerUid": info.st_uid,
        "groupGid": info.st_gid,
        "mode": mode_string(info.st_mode),
        "readable": os.access(path, os.R_OK),
        "writable": os.access(path, os.W_OK),
        "aclForUser": acl_for(path, username),
    }


def collect_devices(tty: str, username: str) -> list[dict[str, Any]]:
    candidates: list[tuple[str, str]] = []
    for pattern, kind in (
        ("/dev/dri/card*", "drm-primary"),
        ("/dev/dri/renderD*", "drm-render"),
        ("/dev/input/event*", "input"),
        ("/dev/nvidia*", "nvidia"),
    ):
        candidates.extend((path, kind) for path in glob.glob(pattern))
    if tty:
        candidates.append((f"/dev/{tty}", "session-tty"))
    candidates.append(("/dev/tty0", "tty-control"))
    records = []
    for raw_path, kind in sorted(set(candidates)):
        path = pathlib.Path(raw_path)
        try:
            records.append(device_record(path, kind, username))
        except (FileNotFoundError, PermissionError):
            continue
    return records


def socket_record(path: pathlib.Path) -> dict[str, Any]:
    try:
        info = path.stat()
    except FileNotFoundError:
        return {"path": str(path), "present": False, "socket": False}
    return {
        "path": str(path),
        "present": True,
        "socket": stat.S_ISSOCK(info.st_mode),
        "ownerUid": info.st_uid,
        "mode": mode_string(info.st_mode),
    }


def git_state() -> dict[str, Any]:
    revision = run(["git", "-C", str(ROOT), "rev-parse", "HEAD"])
    status = run(["git", "-C", str(ROOT), "status", "--porcelain"])
    return {
        "revision": revision.stdout.strip() if revision.returncode == 0 else "unavailable",
        "dirty": bool(status.stdout.strip()) if status.returncode == 0 else None,
    }


def any_rw(devices: list[dict[str, Any]], kind: str) -> bool:
    return any(
        item["kind"] == kind
        and item.get("characterDevice", True)
        and item["readable"]
        and item["writable"]
        for item in devices
    )


def evaluate_record(record: dict[str, Any]) -> dict[str, Any]:
    if record.get("schemaVersion") != SCHEMA_VERSION:
        raise ProbeError("unsupported probe schemaVersion")
    session = record.get("session")
    runtime = record.get("runtime")
    devices = record.get("devices")
    docker = record.get("docker")
    gdm = record.get("gdm")
    if not isinstance(session, dict) or not isinstance(runtime, dict) or not isinstance(devices, list) or not isinstance(docker, dict) or not isinstance(gdm, dict):
        raise ProbeError("malformed probe record")
    checks = {
        "localActiveSeat": session.get("active") is True and session.get("remote") is False and bool(session.get("seat")),
        "assignedTty": bool(session.get("tty")) and isinstance(session.get("vtnr"), int) and session.get("vtnr", 0) > 0,
        "userSessionClass": session.get("class") == "user",
        "runtimeOwned": runtime.get("present") is True and runtime.get("ownerUid") == record.get("identity", {}).get("uid"),
        "sessionBus": runtime.get("sessionBus", {}).get("socket") is True,
        "pipeWire": runtime.get("pipeWire", {}).get("socket") is True,
        "drmPrimaryReadWrite": any_rw(devices, "drm-primary"),
        "drmRenderReadWrite": any_rw(devices, "drm-render"),
        "nvidiaReadWrite": any_rw(devices, "nvidia"),
        "gdmWaylandEnabled": gdm.get("waylandEnabled") is True,
    }
    seat_viable = all(value for name, value in checks.items() if name != "gdmWaylandEnabled")
    base_viable = seat_viable and checks["gdmWaylandEnabled"]
    raw_input = any_rw(devices, "input")
    docker_reachable = docker.get("reachable") is True
    placement = "container-with-narrow-host-service" if seat_viable else "blocked"
    blockers = [name for name, passed in checks.items() if not passed]
    return {
        "status": "candidate" if base_viable else "blocked",
        "compositorPlacement": placement,
        "checks": checks,
        "blockers": blockers,
        "observations": {
            "rawInputAvailableToUser": raw_input,
            "dockerAvailableToUser": docker_reachable,
        },
        "rationale": (
            "The GDM/logind user session owns an active local seat, VT, runtime sockets, DRM, and NVIDIA access. "
            "Raw input and Docker remain unavailable to the unprivileged user, so a fixed root service must start "
            "the reviewed containers and pass only the assigned seat devices."
            if base_viable else
            "The logind seat supports the narrow-service container architecture, but GDM has Wayland disabled. "
            "Do not install a Wayland session or change GDM policy without an explicit, reversible design decision."
            if seat_viable and not checks["gdmWaylandEnabled"] else
            "The current session is missing one or more capabilities required for a GDM-owned Quattro session. "
            "Do not install a session entry or change GDM policy until the blockers are explicitly resolved."
        ),
        "requiredServiceCapabilities": [
            "validate the active local user session, seat, and assigned VT",
            "start only the reviewed Hyprland and Quickshell containers",
            "pass the assigned session TTY, tty0, DRM, input, and NVIDIA runtime devices",
            "label and stop only resources owned by the validated run ID",
            "archive evidence and return control to GDM on exit or failure",
        ] if seat_viable else [],
        "prohibitedCapabilities": [
            "caller-supplied commands or arguments",
            "Docker socket exposure to the session or Quickshell",
            "writable host home mounts",
            "stopping or replacing GDM",
            "automatic login or default-session changes",
        ],
        "requiresPhysicalValidation": [
            "DRM master transfer on the GDM-assigned VT",
            "keyboard and mouse input inside the compositor container",
            "normal logout and bounded failure return to GDM",
        ] if seat_viable else [],
    }


def capture(session_request: str) -> dict[str, Any]:
    uid = os.getuid()
    username = pwd.getpwuid(uid).pw_name
    session_id, raw_session = resolve_session(session_request, uid)
    runtime_path = pathlib.Path(f"/run/user/{uid}")
    try:
        runtime_info = runtime_path.stat()
        runtime = {
            "path": str(runtime_path),
            "present": True,
            "ownerUid": runtime_info.st_uid,
            "mode": mode_string(runtime_info.st_mode),
        }
    except FileNotFoundError:
        runtime = {"path": str(runtime_path), "present": False, "ownerUid": None, "mode": None}
    runtime["sessionBus"] = socket_record(runtime_path / "bus")
    runtime["pipeWire"] = socket_record(runtime_path / "pipewire-0")
    runtime["waylandSockets"] = [
        socket_record(path) for path in sorted(runtime_path.glob("wayland-*"))
        if not path.name.endswith(".lock")
    ]
    tty = raw_session.get("TTY", "")
    devices = collect_devices(tty, username)
    docker_result = run(["docker", "info"], timeout=5)
    docker_socket = pathlib.Path("/var/run/docker.sock")
    gdm_config_path = pathlib.Path("/etc/gdm3/custom.conf")
    gdm_config = configparser.ConfigParser()
    loaded_gdm_config = bool(gdm_config.read(gdm_config_path, encoding="utf-8"))
    wayland_raw = gdm_config.get("daemon", "WaylandEnable", fallback=None) if loaded_gdm_config else None
    # Unknown policy fails closed. This probe is an integration gate, not an
    # attempt to reproduce every implicit GDM default or runtime override.
    wayland_enabled = bool(wayland_raw and wayland_raw.strip().lower() in ("1", "yes", "true", "on"))
    record: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "capturedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "repository": git_state(),
        "identity": {
            "uid": uid,
            "gid": os.getgid(),
            "user": username,
            "groups": sorted(os.getgroups()),
        },
        "session": {
            "id": session_id,
            "userUid": int(raw_session.get("User", "-1")),
            "user": raw_session.get("Name", ""),
            "active": raw_session.get("Active") == "yes",
            "state": raw_session.get("State", ""),
            "remote": raw_session.get("Remote") == "yes",
            "type": raw_session.get("Type", ""),
            "class": raw_session.get("Class", ""),
            "seat": raw_session.get("Seat", ""),
            "tty": tty,
            "vtnr": int(raw_session.get("VTNr") or 0),
            "service": raw_session.get("Service", ""),
            "scope": raw_session.get("Scope", ""),
            "leader": int(raw_session.get("Leader") or 0),
        },
        "probeProcessEnvironment": {
            key: os.environ.get(key) for key in (
                "XDG_SESSION_ID", "XDG_RUNTIME_DIR", "DISPLAY", "WAYLAND_DISPLAY",
                "DESKTOP_SESSION", "GDMSESSION", "DBUS_SESSION_BUS_ADDRESS",
            ) if os.environ.get(key)
        },
        "runtime": runtime,
        "devices": devices,
        "docker": {
            "socket": str(docker_socket),
            "socketReadable": os.access(docker_socket, os.R_OK),
            "socketWritable": os.access(docker_socket, os.W_OK),
            "reachable": docker_result.returncode == 0,
            "detail": (docker_result.stderr or docker_result.stdout).strip()[:500],
        },
        "gdm": {
            "configPath": str(gdm_config_path),
            "configReadable": loaded_gdm_config,
            "waylandEnabled": wayland_enabled,
            "waylandSetting": wayland_raw,
            "waylandSessions": sorted(path.name for path in pathlib.Path("/usr/share/wayland-sessions").glob("*.desktop")),
            "xSessions": sorted(path.name for path in pathlib.Path("/usr/share/xsessions").glob("*.desktop")),
        },
    }
    record["decision"] = evaluate_record(record)
    return record


def atomic_write(path: pathlib.Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(temporary, path)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("--session", default="auto")
    capture_parser.add_argument("--output", type=pathlib.Path)
    evaluate_parser = subparsers.add_parser("evaluate")
    evaluate_parser.add_argument("--input", required=True, type=pathlib.Path)
    args = parser.parse_args()
    try:
        if args.operation == "capture":
            record = capture(args.session)
            if args.output:
                atomic_write(args.output, record)
        else:
            with args.input.open(encoding="utf-8") as handle:
                record = json.load(handle)
            record = evaluate_record(record)
        print(json.dumps(record, indent=2, sort_keys=True))
        return 0 if record.get("decision", record).get("status") == "candidate" else 1
    except (OSError, ValueError, json.JSONDecodeError, ProbeError) as exc:
        print(f"session probe failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
