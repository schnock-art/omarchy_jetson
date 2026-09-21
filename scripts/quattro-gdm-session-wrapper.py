#!/usr/bin/env python3
"""Unprivileged client for the fixed Quattro GDM session control protocol."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import socket
import sys
import uuid
from typing import Any


SCHEMA_VERSION = 1
SOCKET_PATH = pathlib.Path("/run/omarchy-quattro/control.sock")
MAX_RESPONSE_BYTES = 16 * 1024
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
RUN_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$")
OPERATIONS = ("start-session-v1", "stop-session-v1", "collect-session-v1")


class WrapperError(RuntimeError):
    pass


def new_run_id() -> str:
    return f"{dt.datetime.now().strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"


def current_session_id() -> str:
    session_id = os.environ.get("XDG_SESSION_ID", "")
    if not SESSION_ID_RE.fullmatch(session_id):
        raise WrapperError("XDG_SESSION_ID is missing or invalid; start only from a GDM session")
    return session_id


def request(operation: str, run_id: str, session_id: str) -> dict[str, Any]:
    if operation not in OPERATIONS:
        raise WrapperError("operation is not allowlisted")
    if not RUN_ID_RE.fullmatch(run_id):
        raise WrapperError("run ID is invalid")
    if not SESSION_ID_RE.fullmatch(session_id):
        raise WrapperError("session ID is invalid")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "requestId": uuid.uuid4().hex,
        "operation": operation,
        "runId": run_id,
        "sessionId": session_id,
    }


def exchange(value: dict[str, Any], socket_path: pathlib.Path = SOCKET_PATH) -> dict[str, Any]:
    payload = (json.dumps(value, separators=(",", ":")) + "\n").encode()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(15)
            connection.connect(str(socket_path))
            connection.sendall(payload)
            chunks = bytearray()
            while len(chunks) <= MAX_RESPONSE_BYTES:
                part = connection.recv(min(4096, MAX_RESPONSE_BYTES + 1 - len(chunks)))
                if not part:
                    break
                chunks.extend(part)
                if b"\n" in part:
                    break
    except OSError as exc:
        raise WrapperError(f"session service is unavailable: {exc}") from exc
    if len(chunks) > MAX_RESPONSE_BYTES:
        raise WrapperError("session service response exceeded the bounded protocol size")
    line, separator, trailing = bytes(chunks).partition(b"\n")
    if not separator or trailing:
        raise WrapperError("session service returned a malformed response")
    try:
        result = json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WrapperError("session service returned invalid JSON") from exc
    if not isinstance(result, dict) or result.get("requestId") != value["requestId"]:
        raise WrapperError("session service response correlation failed")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=OPERATIONS)
    parser.add_argument("--run-id")
    args = parser.parse_args()
    try:
        if args.operation != "start-session-v1" and not args.run_id:
            raise WrapperError("--run-id is required for stop and collect operations")
        run_id = args.run_id or new_run_id()
        result = exchange(request(args.operation, run_id, current_session_id()))
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0 if result.get("status") == "succeeded" else 1
    except WrapperError as exc:
        print(f"Quattro GDM session wrapper failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
