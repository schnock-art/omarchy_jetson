#!/usr/bin/env python3
"""Fixture coverage for reversible S3 service installation."""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("quattro_gdm_session_install", ROOT / "scripts/quattro-gdm-session-install.py")
assert SPEC and SPEC.loader
INSTALL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = INSTALL
SPEC.loader.exec_module(INSTALL)


class FakeSystem:
    def __init__(self, group_exists: bool = False, member: bool = False, fail_start: bool = False):
        self.group = group_exists
        self.member = member
        self.fail_start = fail_start
        self.commands: list[list[str]] = []

    def run(self, command: list[str], timeout: int = 30) -> subprocess.CompletedProcess[str]:
        del timeout
        self.commands.append(command)
        if command[:2] == ["groupadd", "--system"]:
            self.group = True
        elif command[:2] == ["usermod", "--append"]:
            self.member = True
        elif command[:2] == ["gpasswd", "--delete"]:
            self.member = False
        elif command[0] == "groupdel":
            self.group = False
        if command[:2] == ["systemctl", "start"] and self.fail_start:
            return subprocess.CompletedProcess(command, 1, "", "fixture start failure")
        if command == ["systemctl", "is-enabled", INSTALL.SERVICE_NAME]:
            return subprocess.CompletedProcess(command, 1, "disabled\n", "")
        if command == ["systemctl", "is-active", INSTALL.SERVICE_NAME]:
            return subprocess.CompletedProcess(command, 0, "active\n", "")
        return subprocess.CompletedProcess(command, 0, "", "")

    def group_exists(self) -> bool:
        return self.group

    def user_in_group(self) -> bool:
        return self.member


class InstallTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="quattro-install-")
        self.root = pathlib.Path(self.temporary.name)
        source_root = self.root / "source"
        destination_root = self.root / "installed"
        source_root.mkdir()
        self.files = []
        for name, mode in (("service", 0o755), ("runtime", 0o755), ("common", 0o644), ("unit", 0o644)):
            source = source_root / name
            source.write_text(f"fixture {name}\n", encoding="utf-8")
            self.files.append(INSTALL.InstallFile(source, destination_root / name, mode))
        self.state = self.root / "state/install.json"
        self.system = FakeSystem()
        self.installer = INSTALL.Installer(tuple(self.files), self.state, self.system, require_root_ownership=False)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_install_status_and_uninstall_are_reversible(self) -> None:
        with mock.patch.object(INSTALL.os, "chown"):
            status = self.installer.install()
        self.assertTrue(status["installed"])
        self.assertTrue(status["filesMatch"])
        self.assertTrue(status["serviceActive"])
        self.assertFalse(status["enabledAtBoot"])
        self.assertTrue(self.system.group)
        self.assertTrue(self.system.member)
        for item in self.files:
            self.assertEqual(item.destination.read_bytes(), item.source.read_bytes())

        result = self.installer.uninstall()
        self.assertFalse(result["installed"])
        self.assertFalse(self.system.group)
        self.assertFalse(self.system.member)
        self.assertFalse(self.state.exists())
        self.assertFalse(any(item.destination.exists() for item in self.files))

    def test_existing_destination_fails_without_overwrite(self) -> None:
        self.files[0].destination.parent.mkdir(parents=True)
        self.files[0].destination.write_text("external\n", encoding="utf-8")
        with self.assertRaisesRegex(INSTALL.InstallError, "refusing to overwrite"):
            self.installer.install()
        self.assertEqual(self.files[0].destination.read_text(encoding="utf-8"), "external\n")

    def test_modified_install_refuses_uninstall(self) -> None:
        with mock.patch.object(INSTALL.os, "chown"):
            self.installer.install()
        self.files[0].destination.write_text("modified\n", encoding="utf-8")
        with self.assertRaisesRegex(INSTALL.InstallError, "changed; refusing removal"):
            self.installer.uninstall()
        self.assertTrue(self.state.exists())

    def test_failed_service_start_rolls_back_files_group_and_membership(self) -> None:
        system = FakeSystem(fail_start=True)
        installer = INSTALL.Installer(tuple(self.files), self.state, system, require_root_ownership=False)
        with mock.patch.object(INSTALL.os, "chown"), self.assertRaisesRegex(INSTALL.InstallError, "fixture start failure"):
            installer.install()
        self.assertFalse(system.group)
        self.assertFalse(system.member)
        self.assertFalse(self.state.exists())
        self.assertFalse(any(item.destination.exists() for item in self.files))

    def test_plan_declares_no_gdm_or_boot_change(self) -> None:
        plan = self.installer.plan()
        self.assertFalse(plan["changesGdm"])
        self.assertFalse(plan["enabledAtBoot"])


if __name__ == "__main__":
    unittest.main()
