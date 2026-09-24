#!/usr/bin/env python3
"""Fixture coverage for the S4 GDM session wrapper lifecycle."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("quattro_gdm_session_wrapper", ROOT / "scripts/quattro-gdm-session-wrapper.py")
assert SPEC and SPEC.loader
WRAPPER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = WRAPPER
SPEC.loader.exec_module(WRAPPER)

SERVICE_SPEC = importlib.util.spec_from_file_location(
    "quattro_gdm_session_service_for_wrapper_test",
    ROOT / "scripts/quattro-gdm-session-service.py",
)
assert SERVICE_SPEC and SERVICE_SPEC.loader
SERVICE = importlib.util.module_from_spec(SERVICE_SPEC)
sys.modules[SERVICE_SPEC.name] = SERVICE
SERVICE_SPEC.loader.exec_module(SERVICE)


class Exchange:
    def __init__(self, statuses: list[str], fail_start: bool = False):
        self.statuses = statuses
        self.fail_start = fail_start
        self.operations: list[str] = []

    def __call__(self, request: dict[str, Any]) -> dict[str, Any]:
        operation = request["operation"]
        self.operations.append(operation)
        result = {"schemaVersion": 1, "requestId": request["requestId"], "runId": request["runId"], "operation": operation}
        if operation == "start-session-v1" and self.fail_start:
            return {**result, "status": "failed", "code": "fixture", "message": "start failed"}
        if operation == "status-session-v1":
            return {**result, "status": "succeeded", "code": "status", "message": "status", "sessionState": self.statuses.pop(0)}
        return {**result, "status": "succeeded", "code": "ok", "message": "ok"}


class WrapperTests(unittest.TestCase):
    def test_startup_response_timeout_covers_the_service_start_bound(self) -> None:
        # A client timeout at or below the service's bound can tear down the
        # GDM session while a valid startup is still completing. Keep explicit
        # transport/delivery headroom beyond the runtime readiness wait.
        self.assertGreaterEqual(
            WRAPPER.RESPONSE_TIMEOUT_SECONDS,
            SERVICE.FixedContainerRuntime.START_TIMEOUT + 5,
        )

    def test_normal_session_waits_for_exit_and_collects(self) -> None:
        exchange = Exchange(["running", "stopped"])
        result = WRAPPER.run_session("17", "run-1", exchange_fn=exchange, sleep_fn=lambda _seconds: None)
        self.assertEqual(result, 0)
        self.assertEqual(exchange.operations, [
            "start-session-v1", "status-session-v1", "status-session-v1", "collect-session-v1",
        ])

    def test_signal_path_stops_then_collects(self) -> None:
        exchange = Exchange(["stopped"])
        result = WRAPPER.run_session("17", "run-1", exchange_fn=exchange, should_stop=lambda: True, sleep_fn=lambda _seconds: None)
        self.assertEqual(result, 0)
        self.assertEqual(exchange.operations, [
            "start-session-v1", "stop-session-v1", "status-session-v1", "collect-session-v1",
        ])

    def test_failed_runtime_collects_and_returns_nonzero(self) -> None:
        exchange = Exchange(["failed"])
        result = WRAPPER.run_session("17", "run-1", exchange_fn=exchange, sleep_fn=lambda _seconds: None)
        self.assertEqual(result, 1)
        self.assertEqual(exchange.operations[-1], "collect-session-v1")

    def test_failed_start_never_polls_or_collects(self) -> None:
        exchange = Exchange([], fail_start=True)
        with self.assertRaisesRegex(WRAPPER.WrapperError, "start-session-v1 failed"):
            WRAPPER.run_session("17", "run-1", exchange_fn=exchange)
        self.assertEqual(exchange.operations, ["start-session-v1"])


if __name__ == "__main__":
    unittest.main()
