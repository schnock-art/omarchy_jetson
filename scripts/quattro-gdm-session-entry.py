#!/usr/bin/env python3
"""Install the reversible opt-in Quattro GDM Wayland session entry."""

from __future__ import annotations

import argparse
import configparser
import datetime as dt
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parent.parent
STATE_PATH = pathlib.Path("/var/lib/omarchy-quattro/session-entry.json")
S3_STATE_PATH = pathlib.Path("/var/lib/omarchy-quattro/install.json")
SOCKET_PATH = pathlib.Path("/run/omarchy-quattro/control.sock")
SERVICE_NAME = "omarchy-quattro-session.service"
GDM_CONFIG = pathlib.Path("/etc/gdm3/custom.conf")
ACCOUNT_RECORD = pathlib.Path("/var/lib/AccountsService/users/looco")
SCHEMA_VERSION = 1


class EntryError(RuntimeError):
    pass


@dataclass(frozen=True)
class EntryFile:
    source: pathlib.Path
    destination: pathlib.Path
    mode: int


def default_files() -> tuple[EntryFile, ...]:
    return (
        EntryFile(ROOT / "scripts/quattro-gdm-session-wrapper.py", pathlib.Path("/usr/libexec/omarchy-quattro/session-wrapper"), 0o755),
        EntryFile(ROOT / "gdm/omarchy-quattro.desktop", pathlib.Path("/usr/share/wayland-sessions/omarchy-quattro.desktop"), 0o644),
    )


def s3_sources() -> dict[pathlib.Path, pathlib.Path]:
    return {
        pathlib.Path("/usr/libexec/omarchy-quattro/session-service"): ROOT / "scripts/quattro-gdm-session-service.py",
        pathlib.Path("/usr/libexec/omarchy-quattro/session-runtime"): ROOT / "scripts/quattro-gdm-session-runtime.sh",
        pathlib.Path("/usr/libexec/omarchy-quattro/quattro-session-common.sh"): ROOT / "scripts/quattro-session-common.sh",
        pathlib.Path("/usr/libexec/omarchy-quattro/quattro-session-services.sh"): ROOT / "scripts/quattro-session-services.sh",
        pathlib.Path("/etc/systemd/system/omarchy-quattro-session.service"): ROOT / "systemd/omarchy-quattro-session.service",
    }


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def optional_sha256(path: pathlib.Path) -> str | None:
    return sha256(path) if path.is_file() and not path.is_symlink() else None


def atomic_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, mode=0o755, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, check=False, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(command, 124, "", str(exc))


class EntryInstaller:
    def __init__(
        self,
        files: tuple[EntryFile, ...] = default_files(),
        state_path: pathlib.Path = STATE_PATH,
        s3_state_path: pathlib.Path = S3_STATE_PATH,
        require_root_ownership: bool = True,
        active_state_root: pathlib.Path = pathlib.Path("/run/omarchy-quattro/sessions"),
        runtime_state_root: pathlib.Path = pathlib.Path("/run/omarchy-quattro/runtime"),
        gdm_config: pathlib.Path = GDM_CONFIG,
        account_record: pathlib.Path = ACCOUNT_RECORD,
    ):
        self.files = files
        self.state_path = state_path
        self.s3_state_path = s3_state_path
        self.require_root_ownership = require_root_ownership
        self.active_state_root = active_state_root
        self.runtime_state_root = runtime_state_root
        self.gdm_config = gdm_config
        self.account_record = account_record

    def _validate_desktop(self) -> None:
        desktop = next((item.source for item in self.files if item.destination.name.endswith(".desktop")), None)
        if desktop is None:
            raise EntryError("reviewed GDM desktop entry is missing")
        parser = configparser.ConfigParser(interpolation=None)
        try:
            parser.read(desktop, encoding="utf-8")
            entry = parser["Desktop Entry"]
        except (OSError, KeyError, configparser.Error) as exc:
            raise EntryError("GDM desktop entry is invalid") from exc
        expected = {
            "Name": "Quattro (Jetson preview)",
            "Exec": "/usr/libexec/omarchy-quattro/session-wrapper run-session",
            "TryExec": "/usr/libexec/omarchy-quattro/session-wrapper",
            "Type": "Application",
            "X-GDM-SessionRegisters": "true",
        }
        for key, value in expected.items():
            if entry.get(key) != value:
                raise EntryError(f"GDM desktop entry has unexpected {key}")

    def _load_json(self, path: pathlib.Path, label: str) -> dict[str, Any]:
        if path.is_symlink() or not path.is_file():
            raise EntryError(f"{label} state is missing or unsafe")
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise EntryError(f"{label} state is invalid") from exc
        if not isinstance(value, dict) or value.get("schemaVersion") != SCHEMA_VERSION:
            raise EntryError(f"{label} state contract mismatch")
        return value

    def _matches(self, path: pathlib.Path, record: dict[str, Any]) -> bool:
        if path.is_symlink() or not path.is_file() or sha256(path) != record["sha256"]:
            return False
        info = path.stat()
        if (info.st_mode & 0o777) != int(record["mode"], 8):
            return False
        return not self.require_root_ownership or (info.st_uid == 0 and info.st_gid == 0)

    def _require_current_s3(self) -> None:
        state = self._load_json(self.s3_state_path, "S3 installation")
        records = {pathlib.Path(item["destination"]): item for item in state.get("files", [])}
        for destination, source in s3_sources().items():
            record = records.get(destination)
            if record is None or not self._matches(destination, record):
                raise EntryError(f"S3 installed file is missing or changed: {destination}")
            if sha256(destination) != sha256(source):
                raise EntryError("S3 service must be transactionally refreshed before installing the S4 entry")
        active = run(["systemctl", "is-active", SERVICE_NAME]).returncode == 0
        if not active or not SOCKET_PATH.is_socket():
            raise EntryError("S3 service and control socket must be active")

    def plan(self) -> dict[str, Any]:
        self._validate_desktop()
        records = []
        for item in self.files:
            if item.source.is_symlink() or not item.source.is_file():
                raise EntryError(f"required source is missing or unsafe: {item.source}")
            try:
                source_label = str(item.source.relative_to(ROOT))
            except ValueError:
                source_label = str(item.source)
            records.append({
                "source": source_label,
                "destination": str(item.destination),
                "mode": oct(item.mode),
                "sha256": sha256(item.source),
                "destinationExists": item.destination.exists() or item.destination.is_symlink(),
            })
        return {
            "schemaVersion": SCHEMA_VERSION,
            "operation": "opt-in-s4-wayland-entry",
            "displayName": "Quattro (Jetson preview)",
            "changesGdmConfig": False,
            "changesDefaultSession": False,
            "enablesAutomaticLogin": False,
            "enablesServiceAtBoot": False,
            "files": records,
        }

    def _write_file(self, item: EntryFile) -> None:
        item.destination.parent.mkdir(parents=True, mode=0o755, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=f".{item.destination.name}.", dir=item.destination.parent)
        try:
            os.fchmod(descriptor, item.mode)
            with item.source.open("rb") as source, os.fdopen(descriptor, "wb") as target:
                shutil.copyfileobj(source, target)
                target.flush()
                os.fsync(target.fileno())
            os.chown(temporary, 0, 0)
            os.replace(temporary, item.destination)
        except BaseException:
            pathlib.Path(temporary).unlink(missing_ok=True)
            raise

    def status(self) -> dict[str, Any]:
        if not self.state_path.exists() and not self.state_path.is_symlink():
            return {"schemaVersion": 1, "installed": False}
        state = self._load_json(self.state_path, "S4 entry")
        matches = [self._matches(pathlib.Path(record["destination"]), record) for record in state["files"]]
        source_by_destination = {str(item.destination): item.source for item in self.files}
        source_matches = [
            record["destination"] in source_by_destination
            and sha256(source_by_destination[record["destination"]]) == record["sha256"]
            for record in state["files"]
        ]
        return {
            "schemaVersion": 1,
            "installed": True,
            "filesMatch": all(matches),
            "filesMatchSource": len(source_matches) == len(self.files) and all(source_matches),
            "entryPresent": pathlib.Path(state["entryPath"]).is_file(),
            "changesGdmConfig": False,
            "changesDefaultSession": False,
            "enablesAutomaticLogin": False,
            "gdmConfigMatchesInstallTime": optional_sha256(self.gdm_config) == state.get("gdmConfigSha256AtInstall"),
            "accountRecordMatchesInstallTime": optional_sha256(self.account_record) == state.get("accountRecordSha256AtInstall"),
        }

    def install(self) -> dict[str, Any]:
        if self.state_path.exists() or self.state_path.is_symlink():
            status = self.status()
            if status.get("filesMatch") and status.get("filesMatchSource"):
                return status
            if status.get("filesMatch"):
                raise EntryError("S4 entry is installed but stale; use refresh --approve")
            raise EntryError("S4 entry has installation state but its files changed")
        self._require_current_s3()
        plan = self.plan()
        occupied = [record["destination"] for record in plan["files"] if record["destinationExists"]]
        if occupied:
            raise EntryError(f"refusing to overwrite existing paths: {', '.join(occupied)}")
        gdm_before = optional_sha256(self.gdm_config)
        account_before = optional_sha256(self.account_record)
        installed: list[pathlib.Path] = []
        try:
            for item in self.files:
                self._write_file(item)
                installed.append(item.destination)
            if optional_sha256(self.gdm_config) != gdm_before or optional_sha256(self.account_record) != account_before:
                raise EntryError("GDM or account defaults changed during entry installation")
            state = {
                **plan,
                "installedAt": now(),
                "entryPath": str(next(item.destination for item in self.files if item.destination.name.endswith(".desktop"))),
                "gdmConfigSha256AtInstall": gdm_before,
                "accountRecordSha256AtInstall": account_before,
            }
            atomic_json(self.state_path, state)
            os.chown(self.state_path, 0, 0)
            return self.status()
        except BaseException:
            for path in reversed(installed):
                path.unlink(missing_ok=True)
            self.state_path.unlink(missing_ok=True)
            raise

    def refresh(self) -> dict[str, Any]:
        state = self._load_json(self.state_path, "S4 entry")
        self._require_no_active_run()
        self._require_current_s3()
        records = {record["destination"]: record for record in state.get("files", [])}
        expected = {str(item.destination) for item in self.files}
        if set(records) != expected:
            raise EntryError("installed file set does not match the reviewed S4 entry bundle")
        for destination, record in records.items():
            if not self._matches(pathlib.Path(destination), record):
                raise EntryError(f"installed entry file changed; refusing refresh: {destination}")

        plan = self.plan()
        backups = {item.destination: item.destination.read_bytes() for item in self.files}
        old_modes = {item.destination: item.destination.stat().st_mode & 0o777 for item in self.files}
        old_state = state.copy()
        gdm_before = optional_sha256(self.gdm_config)
        account_before = optional_sha256(self.account_record)
        try:
            for item in self.files:
                self._write_file(item)
            if optional_sha256(self.gdm_config) != gdm_before or optional_sha256(self.account_record) != account_before:
                raise EntryError("GDM or account defaults changed during entry refresh")
            refreshed = {
                **plan,
                "installedAt": state.get("installedAt", now()),
                "refreshedAt": now(),
                "entryPath": str(next(item.destination for item in self.files if item.destination.name.endswith(".desktop"))),
                # Preserve the original installation observations. A separately
                # approved GDM experiment may legitimately be active during a
                # wrapper-only refresh.
                "gdmConfigSha256AtInstall": state.get("gdmConfigSha256AtInstall"),
                "accountRecordSha256AtInstall": state.get("accountRecordSha256AtInstall"),
            }
            atomic_json(self.state_path, refreshed)
            os.chown(self.state_path, 0, 0)
            return self.status()
        except BaseException as exc:
            recovery_error: BaseException | None = None
            try:
                for item in self.files:
                    restore = EntryFile(item.source, item.destination, old_modes[item.destination])
                    descriptor, temporary = tempfile.mkstemp(
                        prefix=f".{item.destination.name}.", dir=item.destination.parent,
                    )
                    try:
                        os.fchmod(descriptor, restore.mode)
                        with os.fdopen(descriptor, "wb") as target:
                            target.write(backups[item.destination])
                            target.flush()
                            os.fsync(target.fileno())
                        os.chown(temporary, 0, 0)
                        os.replace(temporary, item.destination)
                    except BaseException:
                        pathlib.Path(temporary).unlink(missing_ok=True)
                        raise
                atomic_json(self.state_path, old_state)
                os.chown(self.state_path, 0, 0)
            except BaseException as restore_exc:
                recovery_error = restore_exc
            if recovery_error:
                raise EntryError(f"refresh failed ({exc}); rollback also failed ({recovery_error})") from exc
            raise

    def _require_no_active_run(self) -> None:
        for path in self.active_state_root.glob("*.json"):
            try:
                state = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                raise EntryError(f"cannot verify active session state: {path}") from exc
            if state.get("state") in {"starting", "running", "stopping", "collecting"}:
                run_id = state.get("runId", path.stem)
                runtime_path = self.runtime_state_root / str(run_id) / "status.json"
                try:
                    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    runtime = None
                if (
                    isinstance(runtime, dict)
                    and runtime.get("schemaVersion") == SCHEMA_VERSION
                    and runtime.get("runId") == run_id
                    and runtime.get("state") in {"stopped", "failed"}
                    and runtime.get("archiveReady") is True
                ):
                    continue
                raise EntryError(f"refusing entry change while Quattro run is active: {run_id}")

    def uninstall(self) -> dict[str, Any]:
        if not self.state_path.exists() and not self.state_path.is_symlink():
            return {"schemaVersion": 1, "installed": False}
        state = self._load_json(self.state_path, "S4 entry")
        self._require_no_active_run()
        for record in state["files"]:
            path = pathlib.Path(record["destination"])
            if not self._matches(path, record):
                raise EntryError(f"installed entry file changed; refusing removal: {path}")
        for record in reversed(state["files"]):
            pathlib.Path(record["destination"]).unlink()
        self.state_path.unlink()
        return {"schemaVersion": 1, "installed": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("plan", "install", "refresh", "status", "uninstall"))
    parser.add_argument("--approve", action="store_true")
    args = parser.parse_args()
    try:
        installer = EntryInstaller()
        if args.operation == "plan":
            result = installer.plan()
        else:
            if os.geteuid() != 0:
                raise EntryError(f"{args.operation} must run as root")
            if args.operation in {"install", "refresh", "uninstall"} and not args.approve:
                raise EntryError(f"{args.operation} requires --approve")
            result = getattr(installer, args.operation)()
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (EntryError, OSError, KeyError, ValueError) as exc:
        print(f"Quattro S4 entry failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
