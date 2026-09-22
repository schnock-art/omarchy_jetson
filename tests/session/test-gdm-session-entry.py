#!/usr/bin/env python3
"""Fixture coverage for the reversible S4 GDM entry."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("quattro_gdm_session_entry", ROOT / "scripts/quattro-gdm-session-entry.py")
assert SPEC and SPEC.loader
ENTRY = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ENTRY
SPEC.loader.exec_module(ENTRY)


class EntryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="quattro-entry-")
        self.root = pathlib.Path(self.temporary.name)
        source = self.root / "source"
        installed = self.root / "installed"
        source.mkdir()
        wrapper = source / "session-wrapper"
        wrapper.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        desktop = source / "omarchy-quattro.desktop"
        desktop.write_bytes((ROOT / "gdm/omarchy-quattro.desktop").read_bytes())
        self.files = (
            ENTRY.EntryFile(wrapper, installed / "session-wrapper", 0o755),
            ENTRY.EntryFile(desktop, installed / "omarchy-quattro.desktop", 0o644),
        )
        self.state = self.root / "state/session-entry.json"
        self.active = self.root / "active"
        self.active.mkdir()
        self.gdm_config = self.root / "custom.conf"
        self.gdm_config.write_text("[daemon]\nWaylandEnable=false\n", encoding="utf-8")
        self.account_record = self.root / "account"
        self.account_record.write_text("[User]\nXSession=ubuntu\n", encoding="utf-8")
        self.installer = ENTRY.EntryInstaller(
            self.files, self.state, self.root / "s3.json",
            require_root_ownership=False, active_state_root=self.active,
            gdm_config=self.gdm_config, account_record=self.account_record,
        )
        self.installer._require_current_s3 = mock.Mock()  # type: ignore[method-assign]

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install(self) -> dict:
        with mock.patch.object(ENTRY.os, "chown"):
            return self.installer.install()

    def test_plan_has_no_default_gdm_or_boot_mutation(self) -> None:
        plan = self.installer.plan()
        self.assertEqual(plan["displayName"], "Quattro (Jetson preview)")
        self.assertFalse(plan["changesGdmConfig"])
        self.assertFalse(plan["changesDefaultSession"])
        self.assertFalse(plan["enablesAutomaticLogin"])
        self.assertFalse(plan["enablesServiceAtBoot"])

    def test_install_is_idempotent_and_uninstall_is_reversible(self) -> None:
        status = self.install()
        self.assertTrue(status["installed"])
        self.assertTrue(status["filesMatch"])
        self.assertTrue(status["entryPresent"])
        repeated = self.install()
        self.assertEqual(repeated, status)
        result = self.installer.uninstall()
        self.assertFalse(result["installed"])
        self.assertFalse(self.state.exists())
        self.assertFalse(any(item.destination.exists() for item in self.files))
        self.assertFalse(self.installer.uninstall()["installed"])

    def test_collision_refuses_overwrite(self) -> None:
        self.files[0].destination.parent.mkdir(parents=True)
        self.files[0].destination.write_text("external\n", encoding="utf-8")
        with self.assertRaisesRegex(ENTRY.EntryError, "refusing to overwrite"):
            self.install()
        self.assertEqual(self.files[0].destination.read_text(encoding="utf-8"), "external\n")

    def test_modified_entry_refuses_uninstall(self) -> None:
        self.install()
        self.files[1].destination.write_text("modified\n", encoding="utf-8")
        with self.assertRaisesRegex(ENTRY.EntryError, "changed; refusing removal"):
            self.installer.uninstall()

    def test_active_run_refuses_uninstall(self) -> None:
        self.install()
        (self.active / "run-1.json").write_text(json.dumps({"runId": "run-1", "state": "running"}), encoding="utf-8")
        with self.assertRaisesRegex(ENTRY.EntryError, "run is active"):
            self.installer.uninstall()


if __name__ == "__main__":
    unittest.main()
