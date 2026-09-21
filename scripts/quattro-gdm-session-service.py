#!/usr/bin/env python3
"""Narrow, fixed-operation control boundary for a future GDM Quattro session."""

from __future__ import annotations

import argparse
import datetime as dt
import grp
import json
import os
import pathlib
import re
import signal
import socket
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Any, Protocol


SCHEMA_VERSION = 1
MAX_REQUEST_BYTES = 16 * 1024
SOCKET_PATH = pathlib.Path("/run/omarchy-quattro/control.sock")
STATE_ROOT = pathlib.Path("/run/omarchy-quattro/sessions")
SOCKET_GROUP = "omarchy-quattro"
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$")
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
TTY_RE = re.compile(r"^tty([1-9][0-9]?)$")
OPERATIONS = {
    "start-session-v1",
    "stop-session-v1",
    "collect-session-v1",
}
REQUEST_KEYS = {"schemaVersion", "requestId", "operation", "runId", "sessionId"}
SESSION_PROPERTIES = ("Id", "User", "Active", "State", "Remote", "Type", "Class", "Seat", "TTY", "VTNr", "Service")


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
    def inspect(self, session_id: str, caller_uid: int, require_active: bool) -> SessionIdentity: ...


class LogindInspector:
    def inspect(self, session_id: str, caller_uid: int, require_active: bool) -> SessionIdentity:
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

    def handle(self, untrusted: Any, caller_uid: int) -> dict[str, Any]:
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
            identity = self.inspector.inspect(request["sessionId"], caller_uid, require_active)
            if request["operation"] == "start-session-v1":
                result = self._start(request, state, identity)
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


def peer_uid(connection: socket.socket) -> int:
    credentials = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    _pid, uid, _gid = struct.unpack("3i", credentials)
    return uid


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
                    result = controller.handle(request, peer_uid(connection))
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
        controller = Controller(StateStore(STATE_ROOT), LogindInspector(), FailClosedRuntime())
        serve(controller)
        return 0
    except (ControlError, OSError, KeyError) as exc:
        print(f"Quattro GDM session service failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
