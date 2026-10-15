#!/usr/bin/env python3
"""Isolated release-tool regressions: no compiler, signing, DMG, app, home or devices."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


installer = load("hearth_installer", "install-app.py")
licenses = load("hearth_notices", "bundle-notices.py")


class ShellSyntaxTests(unittest.TestCase):
    def test_invalid_later_script_is_not_silently_skipped(self):
        with tempfile.TemporaryDirectory(prefix="hearth-shell-fixture-") as folder:
            first, later = Path(folder) / "first.sh", Path(folder) / "later with spaces.sh"
            first.write_text("print valid\n")
            later.write_text("if true; then\n")
            command = ["zsh", str(ROOT / "scripts/check-shell-syntax.sh"), str(first), str(later)]
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(str(later), result.stderr)
            later.write_text("print also-valid\n")
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)


class NoticeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hearth-notice-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.app = Path(self.temp.name) / "Hearth.app"
        for relative in licenses.NOTICE_PATHS:
            source = self.root / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(f"Synthetic notice fixture: {relative}\n")

    def test_exact_notices_survive_a_bundle_copy(self):
        licenses.notices(self.app, source_root=self.root)
        copied = Path(self.temp.name) / "copied/Hearth.app"
        shutil.copytree(self.app, copied)
        licenses.notices(copied, verify=True, source_root=self.root)

    def test_missing_or_changed_notice_is_rejected(self):
        licenses.notices(self.app, source_root=self.root)
        target = self.app / "Contents/Resources/LICENSE"
        target.write_text("outdated")
        with self.assertRaises(ValueError):
            licenses.notices(self.app, verify=True, source_root=self.root)
        target.unlink()
        with self.assertRaises(ValueError):
            licenses.notices(self.app, verify=True, source_root=self.root)

    def test_notice_destination_symlink_is_rejected(self):
        resources = self.app / "Contents/Resources"
        resources.mkdir(parents=True)
        (resources / "LICENSE").symlink_to(self.root / "LICENSE")
        with self.assertRaises(ValueError):
            licenses.notices(self.app, source_root=self.root)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hearth-install-fixture-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "build/Hearth.app"
        self.target = root / "Applications/Hearth.app"
        for app, marker in ((self.source, "new"), (self.target, "old")):
            app.mkdir(parents=True)
            (app / "fixture").write_text(marker)

    @staticmethod
    def validate(app):
        if not (app / "fixture").is_file():
            raise ValueError("invalid fixture")

    def install(self, **kwargs):
        defaults = dict(validate=self.validate, copy=shutil.copytree, is_running=lambda _: False)
        defaults.update(kwargs)
        return installer.install(self.source, self.target, **defaults)

    def test_success_retains_previous_bundle_and_source(self):
        backup = self.install()
        self.assertEqual((self.target / "fixture").read_text(), "new")
        self.assertEqual((backup / "fixture").read_text(), "old")
        self.assertTrue(backup.name.startswith(".Hearth-before-install-"))
        self.assertEqual((self.source / "fixture").read_text(), "new")

    def test_first_install_has_no_previous_backup(self):
        shutil.rmtree(self.target)
        self.assertIsNone(self.install())
        self.assertEqual((self.target / "fixture").read_text(), "new")

    def test_failed_copy_preserves_existing_install(self):
        def fail_copy(source, destination):
            raise OSError("fixture copy failure")
        with self.assertRaises(OSError):
            self.install(copy=fail_copy)
        self.assertEqual((self.target / "fixture").read_text(), "old")

    def test_failed_staged_validation_preserves_existing_install(self):
        def reject_staged(app):
            if app != self.source:
                raise ValueError("corrupt copy fixture")
        with self.assertRaises(ValueError):
            self.install(validate=reject_staged)
        self.assertEqual((self.target / "fixture").read_text(), "old")

    def test_running_destination_is_not_replaced(self):
        with self.assertRaises(ValueError):
            self.install(is_running=lambda _: True)
        self.assertEqual((self.target / "fixture").read_text(), "old")

    def test_destination_starting_during_copy_is_not_replaced(self):
        states = iter((False, True))
        with self.assertRaises(ValueError):
            self.install(is_running=lambda _: next(states))
        self.assertEqual((self.target / "fixture").read_text(), "old")

    def test_failed_promotion_rolls_back_previous_app(self):
        rename = installer.os.rename
        calls = []
        def fail_promotion(source, destination):
            calls.append((source, destination))
            if len(calls) == 2:
                raise OSError("fixture promotion failure")
            return rename(source, destination)
        with patch.object(installer.os, "rename", side_effect=fail_promotion):
            with self.assertRaises(OSError):
                self.install()
        self.assertEqual(len(calls), 3)
        self.assertEqual((self.target / "fixture").read_text(), "old")

    def test_failed_rollback_reports_and_retains_previous_app(self):
        rename = installer.os.rename
        calls = []
        def fail_after_backup(source, destination):
            calls.append((source, destination))
            if len(calls) >= 2:
                raise OSError("fixture filesystem failure")
            return rename(source, destination)
        with patch.object(installer.os, "rename", side_effect=fail_after_backup):
            with self.assertRaisesRegex(RuntimeError, "previous app is retained"):
                self.install()
        backups = list(self.target.parent.glob(".Hearth-before-install-*.app.backup"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "fixture").read_text(), "old")
        self.assertEqual((self.source / "fixture").read_text(), "new")

    def test_installation_symlink_is_not_replaced(self):
        shutil.rmtree(self.target)
        self.target.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.install()
        self.assertTrue(self.target.is_symlink())
        self.assertEqual((self.source / "fixture").read_text(), "new")

    def test_source_cannot_be_installation(self):
        with self.assertRaises(ValueError):
            installer.install(self.source, self.source, validate=self.validate)
        self.assertEqual((self.source / "fixture").read_text(), "new")


if __name__ == "__main__":
    unittest.main(verbosity=2)
