#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
CONDUCTOR="$ROOT_DIR/scripts/quattro-mvp.py"

python3 - "$CONDUCTOR" <<'PY'
import ast
import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])
spec = importlib.util.spec_from_file_location("quattro_mvp", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    path = pathlib.Path(directory) / "session.json"
    module.write_session(path, "preflight", run_id="fixture")
    module.write_session(path, "ready-for-handoff", run_id="fixture")
    module.write_session(path, "starting", run_id="fixture")
    module.write_session(path, "ready", run_id="fixture")
    module.write_session(path, "awaiting-visual-check", run_id="fixture")
    try:
        module.write_session(path, "preflight", run_id="fixture")
    except ValueError:
        pass
    else:
        raise AssertionError("invalid session transition was accepted")
    module.ARCHIVES = pathlib.Path(directory) / "runs"
    archive = module.ARCHIVES / "fixture-run"
    archive.mkdir(parents=True)
    module.write_session(archive / "session.json", "awaiting-visual-check", run_id="fixture-run")
    session = json.loads((archive / "session.json").read_text(encoding="utf-8"))
    session["revision"] = "archived-revision"
    (archive / "session.json").write_text(json.dumps(session) + "\n", encoding="utf-8")
    archived_manifest = {
        "schemaVersion": 1,
        "requiredMilestones": ["ARCHIVED_ONLY_MARKER"],
        "fatalPatterns": ["ARCHIVED_FATAL_MARKER"],
        "scenarios": [],
        "visualAssertions": ["fixture visual assertion"],
        "timeouts": {},
        "requiredArtifacts": [
            "session.json", "acceptance-manifest.json",
            "quickshell-quattro-smoke.log", "hyprland-phase2-drm.log",
            "agent-status.json", "agent-run.json", "telemetry.json",
            "workload-registry.json", "action-status.json", "mvp-status.json",
        ],
    }
    (archive / "acceptance-manifest.json").write_text(json.dumps(archived_manifest) + "\n", encoding="utf-8")
    (archive / "quickshell-quattro-smoke.log").write_text("ARCHIVED_ONLY_MARKER\n", encoding="utf-8")
    (archive / "hyprland-phase2-drm.log").write_text("renderer ready\n", encoding="utf-8")
    (archive / "agent-run.json").write_text('{"state":"completed","reason":"fixture"}\n', encoding="utf-8")
    for name in ("agent-status.json", "telemetry.json", "workload-registry.json", "action-status.json", "mvp-status.json"):
        (archive / name).write_text("{}\n", encoding="utf-8")
    (archive / "visual-check.json").write_text('{"passed":true,"reason":"fixture"}\n', encoding="utf-8")
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert module.evaluate(type("Args", (), {"run_id": "fixture-run", "write_result": True})()) == 0
    result = json.loads(output.getvalue())
    assert result["revision"] == "archived-revision"
    assert any(check["id"] == "milestone:ARCHIVED_ONLY_MARKER" for check in result["checks"])
    (archive / "agent-run.json").write_text(
        '{"state":"waiting-for-human","waitingFor":"visual-check","reason":"fixture"}\n',
        encoding="utf-8",
    )
    assert module.resolve_visual_gate(type("Args", (), {"run_id": "fixture-run"})()) == 0
    assert json.loads((archive / "agent-run.json").read_text(encoding="utf-8"))["state"] == "completed"
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert module.evaluate(type("Args", (), {"run_id": "fixture-run", "write_result": True})()) == 0
    assert module.complete_run(type("Args", (), {"run_id": "fixture-run"})()) == 0
    assert json.loads((archive / "session.json").read_text(encoding="utf-8"))["state"] == "complete"
    outside = pathlib.Path(directory) / "outside-evidence.json"
    outside.write_text("{}\n", encoding="utf-8")
    (archive / "escaped-evidence.json").symlink_to(outside)
    try:
        module.archive_file(archive, "escaped-evidence.json")
    except ValueError:
        pass
    else:
        raise AssertionError("archived evaluation followed evidence outside the selected run")
    (archive / "hyprland-phase2-drm.log").write_text("ARCHIVED_FATAL_MARKER\n", encoding="utf-8")
    assert module.evaluate(type("Args", (), {"run_id": "fixture-run", "write_result": True})()) == 1
PY

"$CONDUCTOR" preflight >/dev/null
"$SCRIPT_DIR/test-control-plane.sh"
echo "MVP conductor fixture checks passed"
