#!/usr/bin/env python3
"""Deterministic Quattro MVP session and archived-run evaluator."""

import argparse
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARCHIVES = ROOT / "artifacts" / "quattro-runs"
MANIFEST = ROOT / "mvp" / "acceptance.json"
STATES = {
    "preflight", "ready-for-handoff", "starting", "ready", "testing",
    "awaiting-visual-check", "passed", "failed", "restoring-gdm", "complete",
}
TERMINAL = {"passed", "failed", "complete"}
TRANSITIONS = {
    "preflight": {"preflight", "ready-for-handoff", "failed"},
    "ready-for-handoff": {"starting", "failed"},
    "starting": {"ready", "failed", "restoring-gdm"},
    "ready": {"testing", "awaiting-visual-check", "failed", "restoring-gdm"},
    "testing": {"awaiting-visual-check", "passed", "failed", "restoring-gdm"},
    "awaiting-visual-check": {"testing", "passed", "failed", "restoring-gdm"},
    "passed": {"complete"},
    "failed": {"complete"},
    "restoring-gdm": {"complete", "failed"},
    "complete": set(),
}


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def read_json(path):
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as target:
            json.dump(value, target, indent=2, sort_keys=True)
            target.write("\n")
        os.replace(name, path)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def manifest(path=MANIFEST):
    value = read_json(path)
    if value.get("schemaVersion") != 1:
        raise ValueError("unsupported acceptance manifest schema")
    for key in ("requiredMilestones", "fatalPatterns", "scenarios", "visualAssertions", "requiredArtifacts"):
        if not isinstance(value.get(key), list):
            raise ValueError(f"manifest field {key} must be a list")
    return value


def archive_file(directory, relative):
    """Resolve one regular archive file without following paths outside it."""
    if not isinstance(relative, str):
        raise ValueError("archive path must be a string")
    relative_path = pathlib.PurePosixPath(relative)
    if relative_path.is_absolute() or not relative_path.parts or ".." in relative_path.parts:
        raise ValueError(f"unsafe archive path: {relative}")
    path = directory.joinpath(*relative_path.parts)
    try:
        path.resolve().relative_to(directory.resolve())
    except ValueError as exc:
        raise ValueError(f"archive path escapes selected run: {relative}") from exc
    return path


def run_dir(run_id=None):
    if run_id:
        if not run_id or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for char in run_id):
            raise ValueError("invalid run ID")
        path = ARCHIVES / run_id
        if not path.is_dir():
            raise ValueError(f"run archive does not exist: {run_id}")
        return path
    candidates = sorted((p for p in ARCHIVES.iterdir() if p.is_dir()), key=lambda p: p.stat().st_mtime, reverse=True)
    if not candidates:
        raise ValueError("no Quattro run archive exists")
    return candidates[0]


def git_revision():
    try:
        return subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"


def write_session(path, state, reason=None, result=None, run_id=None):
    if state not in STATES:
        raise ValueError(f"unsupported session state: {state}")
    current = read_json(path) if path.exists() else {}
    old = current.get("state")
    if old and state not in TRANSITIONS.get(old, set()):
        raise ValueError(f"invalid session transition from {old} to {state}")
    current.update({
        "schemaVersion": 1,
        "runId": run_id or current.get("runId") or path.parent.name,
        "state": state,
        "stateChangedAt": now(),
        "revision": current.get("revision") or git_revision(),
    })
    current.setdefault("startedAt", now())
    if result is not None:
        current["result"] = result
    if reason is not None:
        current["reason"] = reason
    if state in TERMINAL:
        current["completedAt"] = current.get("completedAt") or now()
    atomic_json(path, current)
    return current


def preflight():
    errors = []
    try:
        manifest()
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        errors.append(str(exc))
    for relative in ("scripts/check-syntax.sh", "scripts/start-quattro-lab.sh", "scripts/run-hyprland-drm.sh"):
        path = ROOT / relative
        if not path.is_file() or not os.access(path, os.X_OK):
            errors.append(f"missing executable {relative}")
    result = {"schemaVersion": 1, "state": "ready-for-handoff" if not errors else "failed", "errors": errors}
    print(json.dumps(result, indent=2))
    return 0 if not errors else 1


def status(args):
    path = run_dir(args.run_id) / "session.json"
    if not path.is_file():
        print(json.dumps({"schemaVersion": 1, "state": "unknown", "reason": "session.json is missing"}, indent=2))
        return 1
    print(json.dumps(read_json(path), indent=2, sort_keys=True))
    return 0


def evaluate(args):
    directory = run_dir(args.run_id)
    manifest_path = archive_file(directory, "acceptance-manifest.json")
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ValueError("selected run has no regular acceptance-manifest.json")
    spec = manifest(manifest_path)
    checks = []
    for relative in spec["requiredArtifacts"]:
        path = archive_file(directory, relative)
        present = path.is_file() and not path.is_symlink()
        checks.append({"id": f"artifact:{relative}", "passed": present, "detail": "present" if present else "missing"})
    agent_run_path = archive_file(directory, "agent-run.json")
    if agent_run_path.is_file():
        agent_run = read_json(agent_run_path)
        completed = agent_run.get("state") == "completed"
        checks.append({"id": "agent-run", "passed": completed, "detail": agent_run.get("reason", agent_run.get("state", "unknown"))})
    log_files = [archive_file(directory, name) for name in ("quickshell-quattro-smoke.log", "hyprland-phase2-drm.log")]
    logs = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in log_files if path.is_file())
    for marker in spec["requiredMilestones"]:
        passed = marker in logs
        checks.append({"id": f"milestone:{marker}", "passed": passed, "detail": "found" if passed else "missing"})
    for pattern in spec["fatalPatterns"]:
        present = pattern in logs
        checks.append({"id": f"fatal-pattern:{pattern}", "passed": not present, "detail": "absent" if not present else "found"})
    visual_path = archive_file(directory, "visual-check.json")
    if visual_path.is_file():
        visual = read_json(visual_path)
        passed = visual.get("passed") is True
        checks.append({"id": "visual-check", "passed": passed, "detail": visual.get("reason", "recorded")})
    else:
        checks.append({"id": "visual-check", "passed": False, "detail": "human visual-check.json is missing"})
    session_path = archive_file(directory, "session.json")
    session = read_json(session_path) if session_path.is_file() else {}
    revision = session.get("revision", "unavailable")
    passed = all(item["passed"] for item in checks)
    result = {"schemaVersion": 1, "runId": directory.name, "evaluatedAt": now(), "revision": revision, "passed": passed, "checks": checks}
    if args.write_result:
        atomic_json(directory / "acceptance-result.json", result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if passed else 1


def finalize(args):
    if args.run_id and (not args.run_id or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for char in args.run_id)):
        raise ValueError("invalid run ID")
    directory = ARCHIVES / (args.run_id or dt.datetime.now().strftime("%Y%m%d-%H%M%S"))
    directory.mkdir(parents=True, exist_ok=True)
    atomic_json(directory / "acceptance-manifest.json", manifest())
    session = directory / "session.json"
    if not session.exists():
        write_session(session, "preflight", run_id=directory.name)
    print(json.dumps({"runId": directory.name, "path": str(directory), "state": read_json(session)["state"]}, indent=2))
    return 0


def record_visual(args):
    directory = run_dir(args.run_id)
    passed = args.passed == "true"
    result = {
        "schemaVersion": 1,
        "runId": directory.name,
        "passed": passed,
        "reason": args.reason,
        "recordedAt": now(),
    }
    atomic_json(directory / "visual-check.json", result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def resolve_visual_gate(args):
    directory = run_dir(args.run_id)
    visual_path = archive_file(directory, "visual-check.json")
    agent_path = archive_file(directory, "agent-run.json")
    if not visual_path.is_file() or read_json(visual_path).get("passed") is not True:
        raise ValueError("a passing visual-check.json is required")
    if not agent_path.is_file():
        raise ValueError("agent-run.json is missing")
    agent = read_json(agent_path)
    if agent.get("state") != "waiting-for-human":
        raise ValueError("agent is not waiting for a human gate")
    waiting_for = agent.get("waitingFor")
    reason = str(agent.get("reason", ""))
    if waiting_for != "visual-check" and "visual-check.json" not in reason:
        raise ValueError("agent is waiting for a different human gate")
    agent.update({
        "state": "completed",
        "reason": "Agent checks completed; the human visual gate is recorded in visual-check.json.",
        "waitingFor": None,
        "completedAt": now(),
        "updatedAt": now(),
    })
    atomic_json(agent_path, agent)
    print(json.dumps(agent, indent=2, sort_keys=True))
    return 0


def complete_run(args):
    directory = run_dir(args.run_id)
    result_path = archive_file(directory, "acceptance-result.json")
    if not result_path.is_file() or read_json(result_path).get("passed") is not True:
        raise ValueError("a passing acceptance-result.json is required")
    session_path = archive_file(directory, "session.json")
    session = read_json(session_path)
    state = session.get("state")
    if state == "awaiting-visual-check":
        write_session(session_path, "passed", result="passed", run_id=directory.name)
        state = "passed"
    if state == "passed":
        session = write_session(session_path, "complete", result="passed", run_id=directory.name)
    elif state != "complete":
        raise ValueError(f"run cannot be completed from session state {state}")
    else:
        session = read_json(session_path)
    print(json.dumps(session, indent=2, sort_keys=True))
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("preflight", "status", "evaluate", "finalize", "record-visual", "resolve-visual-gate", "complete-run"))
    parser.add_argument("--run-id")
    parser.add_argument("--passed", choices=("true", "false"))
    parser.add_argument("--reason", default="")
    parser.add_argument("--write-result", action="store_true")
    args = parser.parse_args()
    try:
        if args.operation == "record-visual" and args.passed is None:
            parser.error("record-visual requires --passed true|false")
        return {"preflight": lambda: preflight(), "status": lambda: status(args), "evaluate": lambda: evaluate(args), "finalize": lambda: finalize(args), "record-visual": lambda: record_visual(args), "resolve-visual-gate": lambda: resolve_visual_gate(args), "complete-run": lambda: complete_run(args)}[args.operation]()
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"MVP conductor: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
