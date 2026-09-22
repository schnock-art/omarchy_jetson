#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "quattro-gdm-wayland-experiment.py"
spec = importlib.util.spec_from_file_location("quattro_gdm_experiment", SCRIPT)
experiment = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(experiment)


before = b"[daemon]\n# preserve this comment\nWaylandEnable=false\n\n[security]\n"
candidate = experiment.patch_wayland_config(before)
assert candidate == b"[daemon]\n# preserve this comment\nWaylandEnable=true\n\n[security]\n"
assert experiment.patch_wayland_config(b"WaylandEnable = false # note\n") == b"WaylandEnable = true # note\n"

for malformed in (b"WaylandEnable=true\n", b"#WaylandEnable=false\n", b"WaylandEnable=false\nWaylandEnable=false\n"):
    try:
        experiment.patch_wayland_config(malformed)
    except experiment.ExperimentError:
        pass
    else:
        raise AssertionError("unsafe GDM configuration was accepted")

assert experiment.validate_id("20260922-123456") == "20260922-123456"
for unsafe in ("", "../escape", "2026 0922", "arbitrary"):
    try:
        experiment.validate_id(unsafe)
    except experiment.ExperimentError:
        pass
    else:
        raise AssertionError("unsafe experiment ID was accepted")

with tempfile.TemporaryDirectory() as directory:
    fixture = pathlib.Path(directory)
    installed = fixture / "installed.desktop"
    source = fixture / "source.desktop"
    source.write_text("[Desktop Entry]\nName=Quattro\n", encoding="utf-8")
    original_installed = experiment.SESSION_ENTRY_PATH
    original_source = experiment.SESSION_ENTRY_SOURCE
    experiment.SESSION_ENTRY_PATH = installed
    experiment.SESSION_ENTRY_SOURCE = source
    try:
        assert experiment.session_entry_evidence() == {
            "sessionEntryInstalled": False,
            "sessionEntrySha256": None,
            "sessionEntryMatchesRepository": False,
        }
        installed.write_bytes(source.read_bytes())
        evidence = experiment.session_entry_evidence()
        assert evidence["sessionEntryInstalled"] is True
        assert evidence["sessionEntryMatchesRepository"] is True
        assert evidence["sessionEntrySha256"] == experiment.sha256(source.read_bytes())
        installed.unlink()
        installed.symlink_to(source)
        assert experiment.session_entry_evidence()["sessionEntryInstalled"] is False
    finally:
        experiment.SESSION_ENTRY_PATH = original_installed
        experiment.SESSION_ENTRY_SOURCE = original_source

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    manifest_path = root / "manifest.json"
    manifest = {
        "schemaVersion": 1,
        "experimentId": root.name,
        "state": "prepared",
        "events": [],
    }
    experiment.atomic_json(manifest_path, manifest)
    loaded = experiment.load_manifest(root)
    assert loaded["state"] == "prepared"
    experiment.record_event(root, loaded, "fixture", value=True)
    updated = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert updated["events"][-1]["event"] == "fixture"
    assert updated["events"][-1]["value"] is True
    assert not list(root.glob(".manifest.json.*"))

print("GDM Wayland experiment fixture checks passed")
