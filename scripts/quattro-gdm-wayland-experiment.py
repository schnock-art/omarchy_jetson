#!/usr/bin/env python3
"""Prepare and control the reversible GDM Wayland feasibility experiment."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile
from typing import Any


SCHEMA_VERSION = 1
ROOT = pathlib.Path(__file__).resolve().parent.parent
EXPERIMENT_ROOT = ROOT / "artifacts" / "gdm-wayland-experiments"
CONFIG_PATH = pathlib.Path("/etc/gdm3/custom.conf")
PROBE = ROOT / "scripts" / "quattro-session-probe.py"
ID_RE = re.compile(r"^[0-9]{8}-[0-9]{6}(?:-[0-9]+)?$")
WAYLAND_FALSE_RE = re.compile(r"(?im)^(\s*WaylandEnable\s*=\s*)false(\s*(?:#.*)?)$")


class ExperimentError(RuntimeError):
    pass


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(command: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(command, 124, "", str(exc))


def atomic_bytes(path: pathlib.Path, data: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
        os.replace(temporary, path)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise


def atomic_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    atomic_bytes(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())


def validate_id(experiment_id: str) -> str:
    if not ID_RE.fullmatch(experiment_id):
        raise ExperimentError(f"invalid experiment ID: {experiment_id!r}")
    return experiment_id


def bundle_path(experiment_id: str, must_exist: bool = True) -> pathlib.Path:
    path = EXPERIMENT_ROOT / validate_id(experiment_id)
    if path.is_symlink():
        raise ExperimentError("experiment bundle must not be a symlink")
    if must_exist and not path.is_dir():
        raise ExperimentError(f"experiment bundle does not exist: {path}")
    return path


def fixed_file(bundle: pathlib.Path, name: str) -> pathlib.Path:
    path = bundle / name
    if path.is_symlink() or not path.is_file():
        raise ExperimentError(f"missing or unsafe experiment file: {name}")
    return path


def patch_wayland_config(before: bytes) -> bytes:
    try:
        text = before.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ExperimentError("GDM configuration is not UTF-8") from exc
    candidate, replacements = WAYLAND_FALSE_RE.subn(r"\1true\2", text)
    if replacements != 1:
        raise ExperimentError("expected exactly one active WaylandEnable=false setting")
    return candidate.encode("utf-8")


def load_manifest(bundle: pathlib.Path) -> dict[str, Any]:
    path = fixed_file(bundle, "manifest.json")
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ExperimentError(f"invalid experiment manifest: {exc}") from exc
    if manifest.get("schemaVersion") != SCHEMA_VERSION or manifest.get("experimentId") != bundle.name:
        raise ExperimentError("manifest schema or experiment ID mismatch")
    if manifest.get("state") not in {"prepared", "applied", "restarted", "verified", "rolled-back"}:
        raise ExperimentError("manifest has an unknown state")
    return manifest


def record_event(bundle: pathlib.Path, manifest: dict[str, Any], event: str, **fields: Any) -> None:
    manifest.setdefault("events", []).append({"event": event, "at": now(), **fields})
    manifest["updatedAt"] = now()
    atomic_json(bundle / "manifest.json", manifest)


def current_config() -> bytes:
    try:
        return CONFIG_PATH.read_bytes()
    except OSError as exc:
        raise ExperimentError(f"cannot read {CONFIG_PATH}: {exc}") from exc


def require_hash(data: bytes, expected: str, label: str) -> None:
    actual = sha256(data)
    if actual != expected:
        raise ExperimentError(f"{label} hash changed: expected {expected}, found {actual}")


def require_control_channel() -> str:
    if os.environ.get("SSH_CONNECTION"):
        return "ssh"
    if not sys.stdin.isatty():
        raise ExperimentError("run mutating experiment operations from SSH or a physical local VT")
    try:
        tty = os.ttyname(sys.stdin.fileno())
    except OSError as exc:
        raise ExperimentError("cannot resolve the controlling terminal") from exc
    if not re.fullmatch(r"/dev/tty[1-9][0-9]*", tty):
        raise ExperimentError(f"not a physical local VT: {tty}")
    foreground = run(["fgconsole"])
    if foreground.returncode != 0 or tty != f"/dev/tty{foreground.stdout.strip()}":
        raise ExperimentError(f"{tty} is not the foreground console")
    return "local-vt"


def sudo_write_config(data: bytes) -> None:
    command = ["sudo", "/usr/bin/tee", str(CONFIG_PATH)]
    result = subprocess.run(command, input=data, check=False, capture_output=True, timeout=30)
    if result.returncode != 0:
        raise ExperimentError(f"failed to write GDM configuration: {result.stderr.decode(errors='replace').strip()}")
    for command in (
        ["sudo", "/usr/bin/chown", "root:root", str(CONFIG_PATH)],
        ["sudo", "/usr/bin/chmod", "0644", str(CONFIG_PATH)],
    ):
        result_text = run(command)
        if result_text.returncode != 0:
            raise ExperimentError(f"failed to normalize GDM configuration: {result_text.stderr.strip()}")


def prepare(experiment_id: str) -> dict[str, Any]:
    bundle = bundle_path(experiment_id, must_exist=False)
    if bundle.exists():
        raise ExperimentError(f"experiment already exists: {bundle}")
    bundle.mkdir(parents=True, mode=0o700)
    before = current_config()
    candidate = patch_wayland_config(before)
    atomic_bytes(bundle / "gdm-custom.conf.before", before)
    atomic_bytes(bundle / "gdm-custom.conf.candidate", candidate)
    baseline_path = bundle / "baseline-probe.json"
    probe = run([str(PROBE), "capture", "--output", str(baseline_path)])
    if probe.returncode not in (0, 1):
        raise ExperimentError(f"baseline probe failed: {probe.stderr.strip()}")
    revision = run(["git", "-C", str(ROOT), "rev-parse", "HEAD"])
    status = run(["git", "-C", str(ROOT), "status", "--porcelain"])
    gdm = run(["systemctl", "is-active", "gdm3"])
    manifest: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "experimentId": experiment_id,
        "state": "prepared",
        "createdAt": now(),
        "updatedAt": now(),
        "repository": {
            "revision": revision.stdout.strip() if revision.returncode == 0 else "unavailable",
            "dirty": bool(status.stdout.strip()) if status.returncode == 0 else None,
        },
        "configPath": str(CONFIG_PATH),
        "beforeSha256": sha256(before),
        "candidateSha256": sha256(candidate),
        "gdmInitiallyActive": gdm.returncode == 0,
        "automaticLoginChanged": False,
        "defaultSessionChanged": False,
        "sessionEntryInstalled": False,
        "events": [{"event": "prepared", "at": now(), "baselineProbeExit": probe.returncode}],
    }
    atomic_json(bundle / "manifest.json", manifest)
    return manifest


def apply(experiment_id: str, approved: bool, recovery_confirmed: bool) -> dict[str, Any]:
    if not approved or not recovery_confirmed:
        raise ExperimentError("apply requires --approve and --ssh-recovery-confirmed")
    channel = require_control_channel()
    bundle = bundle_path(experiment_id)
    manifest = load_manifest(bundle)
    if manifest["state"] not in {"prepared", "rolled-back"}:
        raise ExperimentError(f"cannot apply from state {manifest['state']}")
    before = fixed_file(bundle, "gdm-custom.conf.before").read_bytes()
    candidate = fixed_file(bundle, "gdm-custom.conf.candidate").read_bytes()
    require_hash(before, manifest["beforeSha256"], "backup")
    require_hash(candidate, manifest["candidateSha256"], "candidate")
    require_hash(current_config(), manifest["beforeSha256"], "installed GDM configuration")
    sudo_write_config(candidate)
    require_hash(current_config(), manifest["candidateSha256"], "installed candidate")
    manifest["state"] = "applied"
    record_event(bundle, manifest, "applied", controlChannel=channel)
    return manifest


def restart(experiment_id: str, approved: bool, recovery_confirmed: bool) -> dict[str, Any]:
    if not approved or not recovery_confirmed:
        raise ExperimentError("restart requires --approve and --ssh-recovery-confirmed")
    channel = require_control_channel()
    bundle = bundle_path(experiment_id)
    manifest = load_manifest(bundle)
    if manifest["state"] not in {"applied", "restarted", "verified"}:
        raise ExperimentError(f"cannot restart GDM from state {manifest['state']}")
    require_hash(current_config(), manifest["candidateSha256"], "installed candidate")
    result = run(["sudo", "/usr/bin/systemctl", "restart", "gdm3"], timeout=60)
    if result.returncode != 0:
        raise ExperimentError(f"GDM restart failed: {result.stderr.strip()}")
    active = run(["systemctl", "is-active", "gdm3"])
    if active.returncode != 0:
        raise ExperimentError("GDM did not become active after restart; run rollback over SSH")
    manifest["state"] = "restarted"
    record_event(bundle, manifest, "gdm-restarted", controlChannel=channel)
    return manifest


def verify(experiment_id: str, expected_type: str) -> tuple[dict[str, Any], bool]:
    bundle = bundle_path(experiment_id)
    manifest = load_manifest(bundle)
    if manifest["state"] not in {"applied", "restarted", "verified"}:
        raise ExperimentError(f"cannot verify from state {manifest['state']}")
    sequence = len(manifest.get("verifications", [])) + 1
    output = bundle / f"verification-{sequence}-{expected_type}.json"
    probe = run([str(PROBE), "capture", "--output", str(output)])
    if probe.returncode not in (0, 1):
        raise ExperimentError(f"verification probe failed: {probe.stderr.strip()}")
    record = json.loads(output.read_text(encoding="utf-8"))
    passed = (
        record.get("session", {}).get("type") == expected_type
        and record.get("gdm", {}).get("waylandEnabled") is True
        and record.get("decision", {}).get("status") == "candidate"
    )
    verification = {
        "expectedType": expected_type,
        "observedType": record.get("session", {}).get("type"),
        "passed": passed,
        "probe": output.name,
        "at": now(),
    }
    manifest.setdefault("verifications", []).append(verification)
    if passed:
        manifest["state"] = "verified"
    record_event(bundle, manifest, "verification", **verification)
    return manifest, passed


def rollback(experiment_id: str, approved: bool, restart_gdm: bool) -> dict[str, Any]:
    if not approved:
        raise ExperimentError("rollback requires --approve")
    channel = require_control_channel()
    bundle = bundle_path(experiment_id)
    manifest = load_manifest(bundle)
    before = fixed_file(bundle, "gdm-custom.conf.before").read_bytes()
    require_hash(before, manifest["beforeSha256"], "backup")
    installed_hash = sha256(current_config())
    if installed_hash not in {manifest["beforeSha256"], manifest["candidateSha256"]}:
        raise ExperimentError("installed GDM configuration differs from both experiment versions; refusing overwrite")
    if installed_hash != manifest["beforeSha256"]:
        sudo_write_config(before)
    require_hash(current_config(), manifest["beforeSha256"], "restored GDM configuration")
    restarted = False
    if restart_gdm:
        result = run(["sudo", "/usr/bin/systemctl", "restart", "gdm3"], timeout=60)
        if result.returncode != 0:
            raise ExperimentError(f"GDM restart after rollback failed: {result.stderr.strip()}")
        restarted = True
    manifest["state"] = "rolled-back"
    record_event(bundle, manifest, "rolled-back", controlChannel=channel, gdmRestarted=restarted)
    return manifest


def status(experiment_id: str) -> dict[str, Any]:
    bundle = bundle_path(experiment_id)
    manifest = load_manifest(bundle)
    installed_hash = sha256(current_config())
    return {
        "manifest": manifest,
        "installedConfigSha256": installed_hash,
        "installedVersion": (
            "before" if installed_hash == manifest["beforeSha256"] else
            "candidate" if installed_hash == manifest["candidateSha256"] else
            "external"
        ),
        "gdmActive": run(["systemctl", "is-active", "gdm3"]).returncode == 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)
    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--experiment-id", default=dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
    for operation in ("status", "apply", "restart", "verify", "rollback"):
        subparser = subparsers.add_parser(operation)
        subparser.add_argument("--experiment-id", required=True)
        if operation in {"apply", "restart", "rollback"}:
            subparser.add_argument("--approve", action="store_true")
        if operation in {"apply", "restart"}:
            subparser.add_argument("--ssh-recovery-confirmed", action="store_true")
        if operation == "verify":
            subparser.add_argument("--expect", required=True, choices=("wayland", "x11"))
        if operation == "rollback":
            subparser.add_argument("--restart-gdm", action="store_true")
    args = parser.parse_args()
    try:
        if args.operation == "prepare":
            result = prepare(args.experiment_id)
            exit_code = 0
        elif args.operation == "status":
            result = status(args.experiment_id)
            exit_code = 0
        elif args.operation == "apply":
            result = apply(args.experiment_id, args.approve, args.ssh_recovery_confirmed)
            exit_code = 0
        elif args.operation == "restart":
            result = restart(args.experiment_id, args.approve, args.ssh_recovery_confirmed)
            exit_code = 0
        elif args.operation == "verify":
            result, passed = verify(args.experiment_id, args.expect)
            exit_code = 0 if passed else 1
        else:
            result = rollback(args.experiment_id, args.approve, args.restart_gdm)
            exit_code = 0
        print(json.dumps(result, indent=2, sort_keys=True))
        return exit_code
    except (ExperimentError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"GDM Wayland experiment failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
