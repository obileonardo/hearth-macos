"""Synthetic anchor-layout tests only; never import installed integrations.

The fixtures represent documented Apple TV/LG snippets, aioamazondevices 16.3.x
and eufy-security-client 4.1.x shapes, not verified upstream source revisions.
"""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

PATCHES = Path(__file__).resolve().parents[2] / "homeassistant" / "patches"
sys.path.insert(0, str(PATCHES))
import patch_safety
import apple_tv_unicast as apple
import amazon_two_page_signin as amazon
import lg_switch_case as lg


class PatchPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def fixture(self, module):
        if module is apple:
            texts = {name: old for name, (old, _) in apple.edits.items()}
        elif module is amazon:
            texts = {"login.py": amazon.anchor + amazon.diag_anchor}
        else:
            texts = {"switch.py": "\n".join(old for old, _ in lg.replacements) + "\n    @override\n    async def async_turn_on(self, **kwargs: Any) -> None:"}
        for name, text in texts.items():
            (self.root / name).write_text(text)
        return texts

    def assert_files(self, texts):
        for name, text in texts.items():
            self.assertEqual((self.root / name).read_text(), text)

    def test_default_check_does_not_write_any_supported_layout(self):
        for module in [apple, amazon, lg]:
            with self.subTest(module=module.__name__):
                originals = self.fixture(module)
                patch_safety.commit(module.plan(self.root))
                self.assert_files(originals)

    def test_apply_is_idempotent_for_each_documented_layout(self):
        for module in [apple, amazon, lg]:
            with self.subTest(module=module.__name__):
                self.fixture(module)
                patch_safety.commit(module.plan(self.root), apply=True)
                first = {path: after for path, _, after in module.plan(self.root)}
                patch_safety.commit(module.plan(self.root), apply=True)
                for path, expected in first.items():
                    self.assertEqual(path.read_text(), expected)

    def test_changed_second_apple_file_does_not_write_first(self):
        originals = self.fixture(apple)
        originals["__init__.py"] = "new unsupported layout\n"
        (self.root / "__init__.py").write_text(originals["__init__.py"])
        with self.assertRaises(ValueError):
            patch_safety.commit(apple.plan(self.root), apply=True)
        self.assert_files(originals)

    def test_missing_amazon_main_anchor_does_not_add_diagnostics(self):
        text = amazon.diag_anchor
        (self.root / "login.py").write_text(text)
        with self.assertRaises(ValueError):
            patch_safety.commit(amazon.plan(self.root), apply=True)
        self.assertEqual((self.root / "login.py").read_text(), text)

    def test_missing_amazon_diagnostic_anchor_does_not_add_main_patch(self):
        (self.root / "login.py").write_text(amazon.anchor)
        with self.assertRaises(ValueError):
            patch_safety.commit(amazon.plan(self.root), apply=True)
        self.assertEqual((self.root / "login.py").read_text(), amazon.anchor)

    def test_repeated_anchor_is_rejected_without_writes(self):
        text = amazon.anchor * 2 + amazon.diag_anchor
        (self.root / "login.py").write_text(text)
        with self.assertRaises(ValueError):
            amazon.plan(self.root)
        self.assertEqual((self.root / "login.py").read_text(), text)

    def test_applied_patch_with_duplicate_original_is_not_accepted(self):
        self.fixture(amazon)
        patch_safety.commit(amazon.plan(self.root), apply=True)
        file = self.root / "login.py"
        file.write_text(file.read_text() + amazon.anchor)
        with self.assertRaises(ValueError):
            amazon.plan(self.root)

    def test_incomplete_marker_is_not_accepted_as_applied(self):
        for module, filename, marker in [(amazon, "login.py", amazon.marker), (lg, "switch.py", lg.marker)]:
            with self.subTest(module=module.__name__):
                originals = self.fixture(module)
                (self.root / filename).write_text(originals[filename] + "\n" + marker)
                with self.assertRaises(ValueError):
                    module.plan(self.root)

    def test_lg_missing_helper_decorator_does_not_write_replacements(self):
        originals = self.fixture(lg)
        text = originals["switch.py"].replace("    @override\n", "")
        (self.root / "switch.py").write_text(text)
        with self.assertRaises(ValueError):
            patch_safety.commit(lg.plan(self.root), apply=True)
        self.assertEqual((self.root / "switch.py").read_text(), text)

    def test_concurrent_change_after_plan_is_not_overwritten(self):
        self.fixture(apple)
        plan = apple.plan(self.root)
        path = self.root / "__init__.py"
        path.write_text("concurrent update")
        with self.assertRaises(ValueError):
            patch_safety.commit(plan, apply=True)
        self.assertEqual(path.read_text(), "concurrent update")
        self.assertEqual((self.root / "config_flow.py").read_text(), apple.edits["config_flow.py"][0])

    def test_io_failure_rolls_back_previously_written_file(self):
        originals = self.fixture(apple)
        write = patch_safety.atomic_write
        def fail_second(path, source):
            if path.name == "__init__.py":
                raise OSError("synthetic write failure")
            write(path, source)
        with patch.object(patch_safety, "atomic_write", side_effect=fail_second):
            with self.assertRaises(OSError):
                patch_safety.commit(apple.plan(self.root), apply=True)
        self.assert_files(originals)

    def test_python_cli_check_works_without_installed_integrations(self):
        for module in [apple, amazon, lg]:
            with self.subTest(module=module.__name__):
                originals = self.fixture(module)
                result = subprocess.run([sys.executable, str(PATCHES / (module.__name__ + ".py")), "--root", str(self.root)], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assert_files(originals)

    @unittest.skipUnless(shutil.which("node"), "Node unavailable; optional bridge fixture not run")
    def test_eufy_dry_run_apply_idempotence_and_changed_layout(self):
        source = (PATCHES / "eufy_identity_person_name.js").read_text()
        # Read exported fixture shapes through a synthetic VM that stops before FS IO.
        script = source[:source.index("// Check every file")]+"\nconsole.log(JSON.stringify(patches));"
        result = subprocess.run(["node", "-e", script, str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        import json
        shapes = json.loads(result.stdout)
        # node -e argument indexing uses the default root; only relative suffixes matter.
        files = [self.root / "push/service.js", self.root / "http/device.js"]
        originals = {}
        for file, shape in zip(files, shapes):
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(shape["anchor"])
            originals[file] = shape["anchor"]
        command = ["node", str(PATCHES / "eufy_identity_person_name.js"), str(self.root)]
        check = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)
        for file, text in originals.items(): self.assertEqual(file.read_text(), text)
        files[1].write_text("changed layout")
        rejected = subprocess.run(command + ["--apply"], capture_output=True, text=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(files[0].read_text(), originals[files[0]])
        files[1].write_text(originals[files[1]])
        for _ in range(2):
            applied = subprocess.run(command + ["--apply"], capture_output=True, text=True)
            self.assertEqual(applied.returncode, 0, applied.stderr)
        for file, shape in zip(files, shapes):
            self.assertEqual(file.read_text(), shape["anchor"] + shape["insert"])


if __name__ == "__main__":
    unittest.main()
