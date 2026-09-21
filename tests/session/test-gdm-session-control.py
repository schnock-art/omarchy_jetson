#!/usr/bin/env python3
"""Fixture coverage for the S3 narrow session control boundary."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("quattro_gdm_session_service", ROOT / "scripts" / "quattro-gdm-session-service.py")
assert SPEC and SPEC.loader
SERVICE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SERVICE
SPEC.loader.exec_module(SERVICE)


class FixtureInspector:
    def __init__(self, owner_uid: int = 2002, active: bool = True):
        self.owner_uid = owner_uid
        self.active = active

    def inspect(self, session_id: str, caller_uid: int, require_active: bool) -> Any:
        if caller_uid != self.owner_uid:
            raise SERVICE.ControlError("unauthorized", "fixture owner mismatch")
        if require_active and not self.active:
            raise SERVICE.ControlError("invalid-session", "fixture session inactive")
        return SERVICE.SessionIdentity(session_id, caller_uid, "seat0", "tty2", 2, "wayland", "gdm-password")


class FixtureRuntime:
    def __init__(self):
        self.calls: list[tuple[str, str]] = []
        self.failure: BaseException | None = None

    def invoke(self, operation: str, run_id: str) -> None:
        self.calls.append((operation, run_id))
        if self.failure:
            failure = self.failure
            self.failure = None
            raise failure

    def start(self, identity: Any, run_id: str) -> None:
        self.invoke("start", run_id)

    def stop(self, identity: Any, run_id: str) -> None:
        self.invoke("stop", run_id)

    def collect(self, identity: Any, run_id: str) -> None:
        self.invoke("collect", run_id)


def request(operation: str, request_id: str, run_id: str = "run-1", session_id: str = "17") -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "requestId": request_id,
        "operation": operation,
        "runId": run_id,
        "sessionId": session_id,
    }


class ControlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="quattro-gdm-control-")
        self.runtime = FixtureRuntime()
        self.inspector = FixtureInspector()
        self.store = SERVICE.StateStore(pathlib.Path(self.temporary.name))
        self.controller = SERVICE.Controller(self.store, self.inspector, self.runtime)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def handle(self, operation: str, request_id: str, run_id: str = "run-1", uid: int = 2002) -> dict[str, Any]:
        return self.controller.handle(request(operation, request_id, run_id), uid)

    def test_normal_lifecycle_and_atomic_state(self) -> None:
        self.assertEqual(self.handle("start-session-v1", "req-start")["code"], "started")
        self.assertEqual(self.handle("stop-session-v1", "req-stop")["code"], "stopped")
        self.assertEqual(self.handle("collect-session-v1", "req-collect")["code"], "collected")
        state_path = pathlib.Path(self.temporary.name) / "run-1.json"
        state = json.loads(state_path.read_text(encoding="utf-8"))
        self.assertEqual(state["state"], "collected")
        self.assertEqual(state["session"]["tty"], "tty2")
        self.assertFalse(list(pathlib.Path(self.temporary.name).glob(".run-1.json.*")))
        self.assertEqual(self.runtime.calls, [("start", "run-1"), ("stop", "run-1"), ("collect", "run-1")])

    def test_malformed_and_unknown_fields_fail_closed(self) -> None:
        malformed = request("start-session-v1", "req-malformed")
        malformed["command"] = "sh"
        result = self.controller.handle(malformed, 2002)
        self.assertEqual(result["code"], "malformed-request")
        self.assertEqual(self.runtime.calls, [])
        result = self.controller.handle(request("start-session-v1", "../escape"), 2002)
        self.assertEqual(result["code"], "malformed-request")

    def test_duplicate_request_is_idempotent_and_duplicate_start_is_rejected(self) -> None:
        first = self.handle("start-session-v1", "req-start")
        repeated = self.handle("start-session-v1", "req-start")
        self.assertEqual(first, repeated)
        self.assertEqual(self.runtime.calls, [("start", "run-1")])
        second = self.handle("start-session-v1", "req-start-2")
        self.assertEqual(second["code"], "invalid-transition")
        self.assertEqual(self.store.load("run-1")["state"], "running")
        self.assertEqual(self.runtime.calls, [("start", "run-1")])

        conflict = self.handle("stop-session-v1", "req-start")
        self.assertEqual(conflict["code"], "request-id-conflict")
        self.assertEqual(self.store.load("run-1")["state"], "running")

    def test_unauthorized_caller_cannot_mutate_owned_run(self) -> None:
        start = self.handle("start-session-v1", "req-start")
        result = self.handle("stop-session-v1", "req-stop", uid=3000)
        self.assertEqual(result["code"], "unauthorized")
        replay = self.handle("start-session-v1", "req-start", uid=3000)
        self.assertEqual(replay["code"], "unauthorized")
        self.assertNotEqual(replay, start)
        self.assertEqual(self.runtime.calls, [("start", "run-1")])

    def test_timeout_is_terminal_and_recoverable(self) -> None:
        self.runtime.failure = TimeoutError("fixture timeout")
        result = self.handle("start-session-v1", "req-start")
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["code"], "runtime-failure")
        state = self.store.load("run-1")
        assert state
        self.assertEqual(state["state"], "failed")
        result = self.handle("stop-session-v1", "req-stop")
        self.assertEqual(result["code"], "stopped")

    def test_interruption_is_terminal_and_collects_after_failed_stop(self) -> None:
        self.handle("start-session-v1", "req-start")
        self.runtime.failure = InterruptedError("fixture interruption")
        result = self.handle("stop-session-v1", "req-stop")
        self.assertEqual(result["status"], "failed")
        self.assertEqual(self.store.load("run-1")["state"], "failed")
        result = self.handle("collect-session-v1", "req-collect")
        self.assertEqual(result["code"], "collected")

    def test_unknown_run_and_invalid_transition_do_not_call_runtime(self) -> None:
        result = self.handle("stop-session-v1", "req-stop", run_id="missing")
        self.assertEqual(result["code"], "unknown-run")
        result = self.handle("collect-session-v1", "req-collect")
        self.assertEqual(result["code"], "unknown-run")
        self.assertEqual(self.runtime.calls, [])

    def test_fail_closed_runtime_cannot_claim_live_start(self) -> None:
        controller = SERVICE.Controller(self.store, self.inspector, SERVICE.FailClosedRuntime())
        result = controller.handle(request("start-session-v1", "req-start"), 2002)
        self.assertEqual(result["code"], "runtime-unavailable")
        self.assertEqual(self.store.load("run-1")["state"], "failed")

    def test_logind_identity_is_derived_and_requires_active_local_wayland(self) -> None:
        valid = "\n".join((
            "Id=17", "User=2002", "Active=yes", "State=active", "Remote=no",
            "Type=wayland", "Class=user", "Seat=seat0", "TTY=tty2", "VTNr=2",
            "Service=gdm-password",
        ))
        with mock.patch.object(SERVICE, "run", return_value=SERVICE.subprocess.CompletedProcess([], 0, valid, "")):
            identity = SERVICE.LogindInspector().inspect("17", 2002, True)
        self.assertEqual(identity.tty, "tty2")
        self.assertEqual(identity.vt_number, 2)

        wrong_owner = valid.replace("User=2002", "User=3000")
        with mock.patch.object(SERVICE, "run", return_value=SERVICE.subprocess.CompletedProcess([], 0, wrong_owner, "")):
            with self.assertRaisesRegex(SERVICE.ControlError, "owner"):
                SERVICE.LogindInspector().inspect("17", 2002, True)

        xorg = valid.replace("Type=wayland", "Type=x11")
        with mock.patch.object(SERVICE, "run", return_value=SERVICE.subprocess.CompletedProcess([], 0, xorg, "")):
            with self.assertRaisesRegex(SERVICE.ControlError, "wayland"):
                SERVICE.LogindInspector().inspect("17", 2002, True)

    def test_protocol_reader_is_bounded_and_requires_one_record(self) -> None:
        left, right = SERVICE.socket.socketpair()
        try:
            right.sendall((json.dumps(request("start-session-v1", "req-start")) + "\n").encode())
            self.assertEqual(SERVICE.read_request(left)["requestId"], "req-start")
        finally:
            left.close()
            right.close()

        left, right = SERVICE.socket.socketpair()
        try:
            right.sendall(b"{}\n{}")
            with self.assertRaisesRegex(SERVICE.ControlError, "exactly one"):
                SERVICE.read_request(left)
        finally:
            left.close()
            right.close()


if __name__ == "__main__":
    unittest.main()
