#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "quattro-session-probe.py"
spec = importlib.util.spec_from_file_location("quattro_session_probe", SCRIPT)
probe = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(probe)


def device(kind: str, available: bool = True):
    return {"kind": kind, "readable": available, "writable": available}


base = {
    "schemaVersion": 1,
    "identity": {"uid": 2002},
    "session": {
        "active": True,
        "remote": False,
        "seat": "seat0",
        "tty": "tty2",
        "vtnr": 2,
        "class": "user",
    },
    "runtime": {
        "present": True,
        "ownerUid": 2002,
        "sessionBus": {"socket": True},
        "pipeWire": {"socket": True},
    },
    "devices": [device("drm-primary"), device("drm-render"), device("nvidia"), device("input", False)],
    "docker": {"reachable": False},
    "gdm": {"waylandEnabled": True},
}

decision = probe.evaluate_record(base)
assert decision["status"] == "candidate"
assert decision["compositorPlacement"] == "container-with-narrow-host-service"
assert decision["observations"]["rawInputAvailableToUser"] is False
assert decision["observations"]["dockerAvailableToUser"] is False
assert decision["requiresPhysicalValidation"]

remote = json.loads(json.dumps(base))
remote["session"]["remote"] = True
assert probe.evaluate_record(remote)["status"] == "blocked"

inactive = json.loads(json.dumps(base))
inactive["session"]["active"] = False
assert probe.evaluate_record(inactive)["status"] == "blocked"

missing_drm = json.loads(json.dumps(base))
missing_drm["devices"] = [device("drm-render"), device("nvidia")]
assert probe.evaluate_record(missing_drm)["status"] == "blocked"

wayland_disabled = json.loads(json.dumps(base))
wayland_disabled["gdm"]["waylandEnabled"] = False
disabled_decision = probe.evaluate_record(wayland_disabled)
assert disabled_decision["status"] == "blocked"
assert "gdmWaylandEnabled" in disabled_decision["blockers"]
assert disabled_decision["compositorPlacement"] == "container-with-narrow-host-service"
assert disabled_decision["requiredServiceCapabilities"]

bad_schema = json.loads(json.dumps(base))
bad_schema["schemaVersion"] = 99
try:
    probe.evaluate_record(bad_schema)
except probe.ProbeError:
    pass
else:
    raise AssertionError("unknown schema was accepted")

try:
    probe.evaluate_record({"schemaVersion": 1})
except probe.ProbeError:
    pass
else:
    raise AssertionError("malformed record was accepted")

assert probe.parse_properties("Active=yes\nSeat=seat0\n") == {"Active": "yes", "Seat": "seat0"}

with tempfile.TemporaryDirectory() as directory:
    output = pathlib.Path(directory) / "probe.json"
    probe.atomic_write(output, {"schemaVersion": 1})
    assert json.loads(output.read_text(encoding="utf-8"))["schemaVersion"] == 1
    assert not list(output.parent.glob(".probe.json.*"))

print("Session capability probe fixture checks passed")
