#!/usr/bin/env python3
"""Narrow, fixed-operation control boundary for a future GDM Quattro session."""

from __future__ import annotations

import argparse
import datetime as dt
import grp
import json
import os
import pathlib
import pwd
import re
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Any, Protocol


SCHEMA_VERSION = 1
MAX_REQUEST_BYTES = 16 * 1024
SOCKET_PATH = pathlib.Path("/run/omarchy-quattro/control.sock")
STATE_ROOT = pathlib.Path("/run/omarchy-quattro/sessions")
SOCKET_GROUP = "omarchy-quattro"
RUNTIME_HELPER = pathlib.Path("/usr/libexec/omarchy-quattro/session-runtime")
RUNTIME_ROOT = pathlib.Path("/run/omarchy-quattro/runtime")
ARCHIVE_ROOT = pathlib.Path("/home/looco/repos/omarchy_jetson/artifacts/quattro-runs")
ACCOUNTS_SERVICE_ROOT = pathlib.Path("/var/lib/AccountsService/users")
MAX_ACCOUNT_RECORD_BYTES = 64 * 1024
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$")
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
TTY_RE = re.compile(r"^tty([1-9][0-9]?)$")
OPERATIONS = {
    "start-session-v1",
    "status-session-v1",
    "stop-session-v1",
    "collect-session-v1",
}
REQUEST_KEYS = {"schemaVersion", "requestId", "operation", "runId", "sessionId"}
SESSION_PROPERTIES = ("Id", "User", "Active", "State", "Remote", "Type", "Class", "Seat", "TTY", "VTNr", "Service", "Scope")


class ControlError(RuntimeError):
    """A closed control-boundary failure with a stable machine code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def atomic_json(path: pathlib.Path, value: dict[str, Any], mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.parent.is_symlink():
        raise ControlError("unsafe-state-root", "session state directory must not be a symlink")
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise


def run(command: list[str], timeout: int = 5) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return subprocess.CompletedProcess(command, 124, "", str(exc))


def parse_properties(raw: str) -> dict[str, str]:
    properties: dict[str, str] = {}
    for line in raw.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            properties[key] = value
    return properties


def parse_account_session(raw: bytes) -> str:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ControlError("unauthorized", "the selected GDM session record is not UTF-8") from exc
    section = ""
    sessions: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue
        if section == "User" and "=" in line:
            key, value = line.split("=", 1)
            if key.strip() == "Session":
                sessions.append(value.strip())
    if len(sessions) != 1 or not ID_RE.fullmatch(sessions[0]):
        raise ControlError("unauthorized", "cannot validate the selected GDM session record")
    return sessions[0]


def selected_account_session(uid: int) -> str:
    try:
        username = pwd.getpwuid(uid).pw_name
    except KeyError as exc:
        raise ControlError("unauthorized", "the peer UID has no local account") from exc
    path = ACCOUNTS_SERVICE_ROOT / username
    flags = os.O_RDONLY | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise ControlError("unauthorized", "cannot open the selected GDM session record") from exc
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise ControlError("unauthorized", "the selected GDM session record is unsafe")
        raw = os.read(descriptor, MAX_ACCOUNT_RECORD_BYTES + 1)
        if len(raw) > MAX_ACCOUNT_RECORD_BYTES:
            raise ControlError("unauthorized", "the selected GDM session record is oversized")
    except OSError as exc:
        raise ControlError("unauthorized", "cannot read the selected GDM session record") from exc
    finally:
        os.close(descriptor)
    return parse_account_session(raw)


def validate_identifier(value: Any, label: str, pattern: re.Pattern[str] = ID_RE) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise ControlError("malformed-request", f"invalid {label}")
    return value


def validate_request(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != REQUEST_KEYS:
        raise ControlError("malformed-request", "request must contain exactly the versioned contract fields")
    if value.get("schemaVersion") != SCHEMA_VERSION:
        raise ControlError("unsupported-version", "unsupported request schemaVersion")
    operation = value.get("operation")
    if operation not in OPERATIONS:
        raise ControlError("unknown-operation", "operation is not allowlisted")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "requestId": validate_identifier(value.get("requestId"), "requestId"),
        "operation": operation,
        "runId": validate_identifier(value.get("runId"), "runId"),
        "sessionId": validate_identifier(value.get("sessionId"), "sessionId", SESSION_ID_RE),
    }


@dataclass(frozen=True)
class SessionIdentity:
    session_id: str
    uid: int
    seat: str
    tty: str
    vt_number: int
    session_type: str
    service: str

    def record(self) -> dict[str, Any]:
        return {
            "sessionId": self.session_id,
            "uid": self.uid,
            "seat": self.seat,
            "tty": self.tty,
            "vtNumber": self.vt_number,
            "type": self.session_type,
            "service": self.service,
        }


class Inspector(Protocol):
    def inspect(self, session_id: str, caller_uid: int, require_active: bool, caller_pid: int | None = None) -> SessionIdentity: ...


class LogindInspector:
    def inspect(self, session_id: str, caller_uid: int, require_active: bool, caller_pid: int | None = None) -> SessionIdentity:
        if caller_uid <= 0:
            raise ControlError("unauthorized", "a non-root local desktop user must own the request")
        arguments = ["loginctl", "show-session", session_id]
        for property_name in SESSION_PROPERTIES:
            arguments.extend(("-p", property_name))
        result = run(arguments)
        if result.returncode != 0:
            raise ControlError("unknown-session", "logind session is unavailable")
        values = parse_properties(result.stdout)
        if values.get("Id") not in (None, "", session_id):
            raise ControlError("session-mismatch", "logind returned a different session")
        try:
            owner_uid = int(values.get("User", "-1"))
            vt_number = int(values.get("VTNr", "0"))
        except ValueError as exc:
            raise ControlError("invalid-session", "logind returned invalid numeric session properties") from exc
        tty = values.get("TTY", "")
        tty_match = TTY_RE.fullmatch(tty)
        checks = {
            "owner": owner_uid == caller_uid,
            "local": values.get("Remote") == "no",
            "userClass": values.get("Class") == "user",
            "seat": values.get("Seat") == "seat0",
            "wayland": values.get("Type") == "wayland",
            "gdm": values.get("Service") == "gdm-password",
            "tty": bool(tty_match) and vt_number == int(tty_match.group(1)) if tty_match else False,
            "active": values.get("Active") == "yes" and values.get("State") == "active",
        }
        required = checks if require_active else {key: value for key, value in checks.items() if key != "active"}
        failed = [key for key, passed in required.items() if not passed]
        if failed:
            code = "unauthorized" if "owner" in failed else "invalid-session"
            raise ControlError(code, f"session validation failed: {', '.join(failed)}")
        if require_active:
            if caller_pid is None or caller_pid <= 1:
                raise ControlError("unauthorized", "start requires a peer process in the requested logind session")
            try:
                cgroup = pathlib.Path(f"/proc/{caller_pid}/cgroup").read_text(encoding="utf-8")
            except OSError as exc:
                raise ControlError("unauthorized", "cannot resolve the peer process session") from exc
            scope = values.get("Scope", "")
            if not scope or not any(line.rstrip().endswith(f"/{scope}") for line in cgroup.splitlines()):
                raise ControlError("unauthorized", "peer process does not belong to the requested logind session")
            if selected_account_session(caller_uid) != "omarchy-quattro":
                raise ControlError("unauthorized", "peer process is not the selected Quattro GDM session")
        return SessionIdentity(
            session_id=session_id,
            uid=owner_uid,
            seat=values["Seat"],
            tty=tty,
            vt_number=vt_number,
            session_type=values["Type"],
            service=values["Service"],
        )


class Runtime(Protocol):
    def start(self, identity: SessionIdentity, run_id: str) -> None: ...
    def stop(self, identity: SessionIdentity, run_id: str) -> None: ...
    def collect(self, identity: SessionIdentity, run_id: str) -> None: ...
    def status(self, run_id: str) -> str: ...


class FailClosedRuntime:
    """Placeholder until the reviewed fixed-container adapter lands in S3b."""

    def _reject(self) -> None:
        raise ControlError("runtime-unavailable", "the fixed GDM-session runtime adapter is not installed")

    def start(self, identity: SessionIdentity, run_id: str) -> None:
        self._reject()

    def stop(self, identity: SessionIdentity, run_id: str) -> None:
        self._reject()

    def collect(self, identity: SessionIdentity, run_id: str) -> None:
        self._reject()

    def status(self, run_id: str) -> str:
        self._reject()


class FixedContainerRuntime:
    """Invoke only the reviewed, root-owned runtime supervisor."""

    START_TIMEOUT = 45
    STOP_TIMEOUT = 30

    def __init__(
        self,
        helper: pathlib.Path = RUNTIME_HELPER,
        runtime_root: pathlib.Path = RUNTIME_ROOT,
        archive_root: pathlib.Path = ARCHIVE_ROOT,
    ):
        self.helper = helper
        self.runtime_root = runtime_root
        self.archive_root = archive_root
        self.processes: dict[str, subprocess.Popen[bytes]] = {}

    def _require_helper(self) -> None:
        try:
            info = self.helper.stat()
        except OSError as exc:
            raise ControlError("runtime-unavailable", "the fixed runtime helper is not installed") from exc
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022 or not os.access(self.helper, os.X_OK):
            raise ControlError("unsafe-runtime", "runtime helper must be root-owned, executable, and not group/world writable")

    def _run_dir(self, run_id: str) -> pathlib.Path:
        validate_identifier(run_id, "runId")
        return self.runtime_root / run_id

    def _status(self, run_id: str) -> dict[str, Any] | None:
        path = self._run_dir(run_id) / "status.json"
        if path.is_symlink():
            raise ControlError("unsafe-runtime-state", "runtime status must not be a symlink")
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return None
        except (OSError, json.JSONDecodeError) as exc:
            raise ControlError("invalid-runtime-state", "runtime status is unreadable") from exc
        if not isinstance(value, dict) or value.get("schemaVersion") != SCHEMA_VERSION or value.get("runId") != run_id:
            raise ControlError("invalid-runtime-state", "runtime status does not match the run")
        return value

    def _wait_for(self, run_id: str, accepted: set[str], timeout: int) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = self._status(run_id)
            if status and status.get("state") in accepted:
                return status
            process = self.processes.get(run_id)
            if process is not None and process.poll() is not None and not status:
                raise ControlError("runtime-failure", "runtime supervisor exited before publishing status")
            time.sleep(0.1)
        raise TimeoutError(f"runtime did not reach {sorted(accepted)} within {timeout} seconds")

    def start(self, identity: SessionIdentity, run_id: str) -> None:
        self._require_helper()
        run_dir = self._run_dir(run_id)
        self.runtime_root.mkdir(parents=True, mode=0o700, exist_ok=True)
        os.chmod(self.runtime_root, 0o700)
        run_dir.mkdir(mode=0o700, exist_ok=False)
        os.chmod(run_dir, 0o700)
        log_path = run_dir / "supervisor.log"
        command = [
            str(self.helper), "supervise", run_id, identity.session_id,
            str(identity.uid), str(pwd.getpwuid(identity.uid).pw_gid), identity.tty,
        ]
        with log_path.open("ab", buffering=0) as log:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log, close_fds=True)
        self.processes[run_id] = process
        try:
            status = self._wait_for(run_id, {"ready", "failed"}, self.START_TIMEOUT)
        except Exception:
            if process.poll() is None:
                process.terminate()
            raise
        if status["state"] != "ready":
            raise ControlError("runtime-failure", "runtime supervisor failed during startup")

    def _validated_pid(self, run_id: str, status: dict[str, Any]) -> int | None:
        pid = status.get("supervisorPid")
        if not isinstance(pid, int) or pid <= 1:
            return None
        try:
            command_line = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        except OSError:
            return None
        expected_helper = os.fsencode(str(self.helper))
        expected_run = os.fsencode(run_id)
        if expected_helper not in command_line or expected_run not in command_line:
            raise ControlError("unsafe-runtime-state", "recorded supervisor PID does not match the fixed helper and run")
        return pid

    def stop(self, identity: SessionIdentity, run_id: str) -> None:
        del identity
        status = self._status(run_id)
        if status is None:
            raise ControlError("runtime-missing", "runtime status is unavailable")
        if status.get("state") in {"stopped", "failed"}:
            return
        pid = self._validated_pid(run_id, status)
        if pid is None:
            raise ControlError("runtime-orphaned", "runtime supervisor is unavailable for bounded cleanup")
        os.kill(pid, signal.SIGTERM)
        self._wait_for(run_id, {"stopped", "failed"}, self.STOP_TIMEOUT)
        process = self.processes.pop(run_id, None)
        if process is not None:
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                raise ControlError("runtime-timeout", "runtime supervisor did not exit after cleanup")

    def collect(self, identity: SessionIdentity, run_id: str) -> None:
        del identity
        status = self._status(run_id)
        if not status or status.get("state") not in {"stopped", "failed"} or status.get("archiveReady") is not True:
            raise ControlError("archive-unavailable", "runtime has not published a complete archive")
        archive = self.archive_root / run_id
        for required in ("session.json", "acceptance-manifest.json"):
            path = archive / required
            if path.is_symlink() or not path.is_file():
                raise ControlError("archive-incomplete", f"runtime archive is missing {required}")

    def status(self, run_id: str) -> str:
        status = self._status(run_id)
        if status is None:
            raise ControlError("runtime-missing", "runtime status is unavailable")
        state = status.get("state")
        mapping = {"starting": "starting", "ready": "running", "stopped": "stopped", "failed": "failed"}
        if state not in mapping:
            raise ControlError("invalid-runtime-state", "runtime published an unknown state")
        return mapping[state]


class StateStore:
    def __init__(self, root: pathlib.Path):
        self.root = root

    def path(self, run_id: str) -> pathlib.Path:
        validate_identifier(run_id, "runId")
        return self.root / f"{run_id}.json"

    def load(self, run_id: str) -> dict[str, Any] | None:
        path = self.path(run_id)
        if path.is_symlink():
            raise ControlError("unsafe-state", "session state must not be a symlink")
        if not path.exists():
            return None
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ControlError("invalid-state", "stored session state is unreadable") from exc
        if not isinstance(value, dict) or value.get("schemaVersion") != SCHEMA_VERSION or value.get("runId") != run_id:
            raise ControlError("invalid-state", "stored session state does not match the contract")
        return value

    def save(self, state: dict[str, Any]) -> None:
        atomic_json(self.path(state["runId"]), state)


def terminal_result(request: dict[str, Any] | None, status: str, code: str, message: str) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "requestId": request.get("requestId") if request else None,
        "runId": request.get("runId") if request else None,
        "operation": request.get("operation") if request else None,
        "status": status,
        "code": code,
        "message": message,
        "completedAt": now(),
    }


class Controller:
    def __init__(self, store: StateStore, inspector: Inspector, runtime: Runtime):
        self.store = store
        self.inspector = inspector
        self.runtime = runtime

    def handle(self, untrusted: Any, caller_uid: int, caller_pid: int | None = None) -> dict[str, Any]:
        request: dict[str, Any] | None = None
        try:
            request = validate_request(untrusted)
            state = self.store.load(request["runId"])
            if state:
                if state.get("ownerUid") != caller_uid or state.get("sessionId") != request["sessionId"]:
                    raise ControlError("unauthorized", "run ownership does not match the caller and session")
                cached = state.get("results", {}).get(request["requestId"])
                if isinstance(cached, dict):
                    if cached.get("operation") != request["operation"]:
                        raise ControlError("request-id-conflict", "requestId was already used for another operation")
                    return cached
            require_active = request["operation"] == "start-session-v1"
            identity = self.inspector.inspect(request["sessionId"], caller_uid, require_active, caller_pid)
            if request["operation"] == "start-session-v1":
                result = self._start(request, state, identity)
            elif request["operation"] == "status-session-v1":
                result = self._status(request, state)
            elif request["operation"] == "stop-session-v1":
                result = self._stop(request, state, identity)
            else:
                result = self._collect(request, state, identity)
            return result
        except ControlError as exc:
            result = terminal_result(request, "failed", exc.code, str(exc))
            if request is not None:
                self._record_failure(request, caller_uid, result)
            return result
        except Exception as exc:
            result = terminal_result(request, "failed", "runtime-failure", str(exc) or type(exc).__name__)
            if request is not None:
                self._record_failure(request, caller_uid, result)
            return result

    def _new_state(self, request: dict[str, Any], identity: SessionIdentity) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "runId": request["runId"],
            "ownerUid": identity.uid,
            "sessionId": identity.session_id,
            "session": identity.record(),
            "state": "new",
            "createdAt": now(),
            "updatedAt": now(),
            "results": {},
        }

    def _transition(self, state: dict[str, Any], name: str) -> None:
        state["state"] = name
        state["updatedAt"] = now()
        self.store.save(state)

    def _finish(self, state: dict[str, Any], request: dict[str, Any], code: str, message: str) -> dict[str, Any]:
        result = terminal_result(request, "succeeded", code, message)
        state.setdefault("results", {})[request["requestId"]] = result
        state["updatedAt"] = now()
        self.store.save(state)
        return result

    def _record_failure(self, request: dict[str, Any], caller_uid: int, result: dict[str, Any]) -> None:
        try:
            state = self.store.load(request["runId"])
            if state is None or state.get("ownerUid") != caller_uid:
                return
            if request["requestId"] in state.setdefault("results", {}):
                return
            state["updatedAt"] = now()
            state["results"][request["requestId"]] = result
            self.store.save(state)
        except ControlError:
            return

    def _start(self, request: dict[str, Any], state: dict[str, Any] | None, identity: SessionIdentity) -> dict[str, Any]:
        if state is not None:
            raise ControlError("invalid-transition", f"cannot start a run in state {state.get('state')}")
        state = self._new_state(request, identity)
        self._transition(state, "starting")
        try:
            self.runtime.start(identity, request["runId"])
        except Exception:
            self._transition(state, "failed")
            raise
        self._transition(state, "running")
        return self._finish(state, request, "started", "fixed Quattro session runtime started")

    def _stop(self, request: dict[str, Any], state: dict[str, Any] | None, identity: SessionIdentity) -> dict[str, Any]:
        if state is None:
            raise ControlError("unknown-run", "cannot stop an unknown run")
        if state["state"] in {"stopped", "collected"}:
            return self._finish(state, request, "already-stopped", "run is already stopped")
        if state["state"] not in {"starting", "running", "failed", "stopping"}:
            raise ControlError("invalid-transition", f"cannot stop a run in state {state['state']}")
        self._transition(state, "stopping")
        try:
            self.runtime.stop(identity, request["runId"])
        except Exception:
            self._transition(state, "failed")
            raise
        self._transition(state, "stopped")
        return self._finish(state, request, "stopped", "fixed Quattro session runtime stopped")

    def _status(self, request: dict[str, Any], state: dict[str, Any] | None) -> dict[str, Any]:
        if state is None:
            raise ControlError("unknown-run", "cannot inspect an unknown run")
        session_state = state["state"]
        if session_state not in {"collected"}:
            runtime_state = self.runtime.status(request["runId"])
            if runtime_state in {"stopped", "failed"} and session_state != runtime_state:
                self._transition(state, runtime_state)
                session_state = runtime_state
            elif runtime_state == "running" and session_state in {"starting", "running"}:
                session_state = "running"
        result = terminal_result(request, "succeeded", "status", "Quattro session state reported")
        result["sessionState"] = session_state
        return result

    def _collect(self, request: dict[str, Any], state: dict[str, Any] | None, identity: SessionIdentity) -> dict[str, Any]:
        if state is None:
            raise ControlError("unknown-run", "cannot collect an unknown run")
        if state["state"] == "collected":
            return self._finish(state, request, "already-collected", "run evidence is already collected")
        if state["state"] not in {"stopped", "failed"}:
            raise ControlError("invalid-transition", f"cannot collect a run in state {state['state']}")
        self._transition(state, "collecting")
        try:
            self.runtime.collect(identity, request["runId"])
        except Exception:
            self._transition(state, "failed")
            raise
        self._transition(state, "collected")
        return self._finish(state, request, "collected", "run evidence collected")


def read_request(connection: socket.socket) -> Any:
    connection.settimeout(10)
    chunks = bytearray()
    while len(chunks) <= MAX_REQUEST_BYTES:
        part = connection.recv(min(4096, MAX_REQUEST_BYTES + 1 - len(chunks)))
        if not part:
            break
        chunks.extend(part)
        if b"\n" in part:
            break
    if len(chunks) > MAX_REQUEST_BYTES:
        raise ControlError("request-too-large", "request exceeds the bounded protocol size")
    line, separator, trailing = bytes(chunks).partition(b"\n")
    if not separator or trailing:
        raise ControlError("malformed-request", "request must be exactly one newline-terminated JSON record")
    try:
        return json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ControlError("malformed-request", "request is not valid UTF-8 JSON") from exc


def peer_credentials(connection: socket.socket) -> tuple[int, int]:
    credentials = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    pid, uid, _gid = struct.unpack("3i", credentials)
    return pid, uid


def serve(controller: Controller, socket_path: pathlib.Path = SOCKET_PATH) -> None:
    if os.geteuid() != 0:
        raise ControlError("root-required", "the session service must run as root")
    group_gid = grp.getgrnam(SOCKET_GROUP).gr_gid
    socket_path.parent.mkdir(parents=True, mode=0o755, exist_ok=True)
    if socket_path.is_symlink():
        raise ControlError("unsafe-socket", "control socket path must not be a symlink")
    socket_path.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    stop_requested = False

    def request_stop(_signum: int, _frame: Any) -> None:
        nonlocal stop_requested
        stop_requested = True
        server.close()

    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, request_stop)
    try:
        server.bind(str(socket_path))
        os.chown(socket_path, 0, group_gid)
        os.chmod(socket_path, 0o660)
        server.listen(8)
        while not stop_requested:
            try:
                connection, _address = server.accept()
            except OSError:
                if stop_requested:
                    break
                raise
            with connection:
                request = None
                try:
                    request = read_request(connection)
                    caller_pid, caller_uid = peer_credentials(connection)
                    result = controller.handle(request, caller_uid, caller_pid)
                except ControlError as exc:
                    result = terminal_result(request if isinstance(request, dict) else None, "failed", exc.code, str(exc))
                connection.sendall((json.dumps(result, sort_keys=True) + "\n").encode())
    finally:
        server.close()
        socket_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("serve", nargs="?", default="serve", choices=("serve",))
    args = parser.parse_args()
    del args
    try:
        controller = Controller(StateStore(STATE_ROOT), LogindInspector(), FixedContainerRuntime())
        serve(controller)
        return 0
    except (ControlError, OSError, KeyError) as exc:
        print(f"Quattro GDM session service failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
