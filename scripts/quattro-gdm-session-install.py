#!/usr/bin/env python3
"""Reversibly install the temporary S3 service without changing GDM."""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import grp
import hashlib
import json
import os
import pathlib
import pwd
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parent.parent
LIBEXEC = pathlib.Path("/usr/libexec/omarchy-quattro")
UNIT_PATH = pathlib.Path("/etc/systemd/system/omarchy-quattro-session.service")
STATE_PATH = pathlib.Path("/var/lib/omarchy-quattro/install.json")
SOCKET_PATH = pathlib.Path("/run/omarchy-quattro/control.sock")
SERVICE_NAME = "omarchy-quattro-session.service"
GROUP_NAME = "omarchy-quattro"
DESKTOP_USER = "looco"
SCHEMA_VERSION = 1


class InstallError(RuntimeError):
    pass


@dataclasses.dataclass(frozen=True)
class InstallFile:
    source: pathlib.Path
    destination: pathlib.Path
    mode: int


def default_files() -> tuple[InstallFile, ...]:
    return (
        InstallFile(ROOT / "scripts/quattro-gdm-session-service.py", LIBEXEC / "session-service", 0o755),
        InstallFile(ROOT / "scripts/quattro-gdm-session-runtime.sh", LIBEXEC / "session-runtime", 0o755),
        InstallFile(ROOT / "scripts/quattro-session-common.sh", LIBEXEC / "quattro-session-common.sh", 0o644),
        InstallFile(ROOT / "scripts/quattro-session-services.sh", LIBEXEC / "quattro-session-services.sh", 0o644),
        InstallFile(ROOT / "systemd/omarchy-quattro-session.service", UNIT_PATH, 0o644),
    )


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


class System:
    def run(self, command: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as exc:
            return subprocess.CompletedProcess(command, 124, "", str(exc))

    def group_exists(self) -> bool:
        try:
            grp.getgrnam(GROUP_NAME)
            return True
        except KeyError:
            return False

    def user_in_group(self) -> bool:
        user = pwd.getpwnam(DESKTOP_USER)
        group = grp.getgrnam(GROUP_NAME)
        return user.pw_gid == group.gr_gid or DESKTOP_USER in group.gr_mem


class Installer:
    def __init__(
        self,
        files: tuple[InstallFile, ...] = default_files(),
        state_path: pathlib.Path = STATE_PATH,
        system: System | None = None,
        require_root_ownership: bool = True,
        socket_path: pathlib.Path = SOCKET_PATH,
    ):
        self.files = files
        self.state_path = state_path
        self.system = system or System()
        self.require_root_ownership = require_root_ownership
        self.socket_path = socket_path

    def _matches(self, path: pathlib.Path, record: dict[str, Any]) -> bool:
        if path.is_symlink() or not path.is_file() or sha256(path) != record["sha256"]:
            return False
        info = path.stat()
        if (info.st_mode & 0o777) != int(record["mode"], 8):
            return False
        return not self.require_root_ownership or (info.st_uid == 0 and info.st_gid == 0)

    def _command(self, command: list[str]) -> None:
        result = self.system.run(command)
        if result.returncode != 0:
            raise InstallError(f"command failed ({' '.join(command)}): {result.stderr.strip()}")

    def _unit_file_state(self) -> str:
        result = self.system.run(["systemctl", "is-enabled", SERVICE_NAME])
        state = result.stdout.strip().splitlines()[0] if result.stdout.strip() else "unknown"
        return state

    @staticmethod
    def _enabled_at_boot(state: str) -> bool:
        return state in {"enabled", "enabled-runtime", "linked", "linked-runtime", "alias"}

    def _remove_empty_install_directories(self) -> None:
        directories = {item.destination.parent for item in self.files}
        directories.add(self.state_path.parent)
        for directory in sorted(directories, key=lambda item: len(item.parts), reverse=True):
            try:
                directory.rmdir()
            except OSError:
                pass

    def _wait_for_socket(self, timeout: float = 5.0) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.socket_path.is_socket():
                return
            time.sleep(0.05)
        raise InstallError(f"service did not publish its control socket within {timeout:g} seconds")

    def _load_state(self) -> dict[str, Any]:
        if self.state_path.is_symlink() or not self.state_path.is_file():
            raise InstallError("installation state is missing or unsafe")
        try:
            value = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise InstallError("installation state is invalid") from exc
        if value.get("schemaVersion") != SCHEMA_VERSION or value.get("service") != SERVICE_NAME:
            raise InstallError("installation state contract mismatch")
        return value

    def plan(self) -> dict[str, Any]:
        records = []
        for item in self.files:
            if item.source.is_symlink() or not item.source.is_file():
                raise InstallError(f"required source is missing or unsafe: {item.source}")
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
            "operation": "temporary-s3-install",
            "service": SERVICE_NAME,
            "enabledAtBoot": False,
            "changesGdm": False,
            "files": records,
        }

    def install(self) -> dict[str, Any]:
        plan = self.plan()
        if self.state_path.exists() or self.state_path.is_symlink():
            raise InstallError("temporary service already has installation state")
        occupied = [record["destination"] for record in plan["files"] if record["destinationExists"]]
        if occupied:
            raise InstallError(f"refusing to overwrite existing paths: {', '.join(occupied)}")
        group_created = not self.system.group_exists()
        membership_added = False
        installed: list[pathlib.Path] = []
        try:
            if group_created:
                self._command(["groupadd", "--system", GROUP_NAME])
            if not self.system.user_in_group():
                self._command(["usermod", "--append", "--groups", GROUP_NAME, DESKTOP_USER])
                membership_added = True
            for item in self.files:
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
                installed.append(item.destination)
            state = {
                **plan,
                "installedAt": now(),
                "groupCreated": group_created,
                "membershipAdded": membership_added,
            }
            atomic_json(self.state_path, state)
            os.chown(self.state_path, 0, 0)
            self._command(["systemctl", "daemon-reload"])
            self._command(["systemctl", "start", SERVICE_NAME])
            self._wait_for_socket()
            unit_state = self._unit_file_state()
            if self._enabled_at_boot(unit_state):
                raise InstallError(f"service unexpectedly became enabled at boot ({unit_state})")
            if unit_state != "static":
                raise InstallError(f"unexpected systemd unit-file state: {unit_state}")
            return self.status()
        except BaseException:
            self.system.run(["systemctl", "stop", SERVICE_NAME])
            for path in reversed(installed):
                path.unlink(missing_ok=True)
            self.state_path.unlink(missing_ok=True)
            if membership_added:
                self.system.run(["gpasswd", "--delete", DESKTOP_USER, GROUP_NAME])
            if group_created:
                self.system.run(["groupdel", GROUP_NAME])
            self.system.run(["systemctl", "daemon-reload"])
            self._remove_empty_install_directories()
            raise

    def status(self) -> dict[str, Any]:
        state = self._load_state()
        files = []
        all_match = True
        for record in state["files"]:
            path = pathlib.Path(record["destination"])
            matches = self._matches(path, record)
            all_match = all_match and matches
            files.append({"path": str(path), "matchesInstalledHash": matches})
        active = self.system.run(["systemctl", "is-active", SERVICE_NAME]).returncode == 0
        unit_state = self._unit_file_state()
        return {
            "schemaVersion": SCHEMA_VERSION,
            "installed": True,
            "filesMatch": all_match,
            "serviceActive": active,
            "enabledAtBoot": self._enabled_at_boot(unit_state),
            "unitFileState": unit_state,
            "socketPresent": self.socket_path.is_socket(),
            "files": files,
        }

    def uninstall(self) -> dict[str, Any]:
        state = self._load_state()
        for record in state["files"]:
            path = pathlib.Path(record["destination"])
            if not self._matches(path, record):
                raise InstallError(f"installed file changed; refusing removal: {path}")
        self._command(["systemctl", "stop", SERVICE_NAME])
        for record in reversed(state["files"]):
            pathlib.Path(record["destination"]).unlink()
        self._command(["systemctl", "daemon-reload"])
        if state.get("membershipAdded"):
            self._command(["gpasswd", "--delete", DESKTOP_USER, GROUP_NAME])
        if state.get("groupCreated"):
            self._command(["groupdel", GROUP_NAME])
        self.state_path.unlink()
        self._remove_empty_install_directories()
        return {"schemaVersion": SCHEMA_VERSION, "installed": False, "serviceActive": False, "enabledAtBoot": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("plan", "install", "status", "uninstall"))
    parser.add_argument("--approve", action="store_true")
    args = parser.parse_args()
    try:
        installer = Installer()
        if args.operation == "plan":
            result = installer.plan()
        else:
            if os.geteuid() != 0:
                raise InstallError(f"{args.operation} must run as root")
            if args.operation in {"install", "uninstall"} and not args.approve:
                raise InstallError(f"{args.operation} requires --approve")
            result = getattr(installer, args.operation)()
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (InstallError, OSError, KeyError, ValueError) as exc:
        print(f"Quattro S3 installation failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
