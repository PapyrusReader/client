"""Fast, database-free regression checks for release decisions."""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

GATE_PATH = Path(__file__).resolve().parents[1] / "release_gate.py"
spec = importlib.util.spec_from_file_location("release_gate", GATE_PATH)
assert spec is not None and spec.loader is not None
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ReleaseGateTest(unittest.TestCase):
    def test_dependency_edit_does_not_release(self) -> None:
        first = gate.parse("version: 1.0.0+1\ndependencies: old\n", "client")
        second = gate.parse("version: 1.0.0+1\ndependencies: new\n", "client")
        self.assertFalse(gate.decide(second, first, "client"))

    def test_each_android_upload_requires_a_new_number(self) -> None:
        self.assertTrue(gate.decide(("1.0.0", 2), ("1.0.0", 1), "client"))
        self.assertTrue(gate.decide(("1.1.0", 3), ("1.0.0", 2), "client"))
        for current in (("1.1.0", 1), ("1.1.0", 2), ("0.9.0", 3)):
            with self.assertRaises(ValueError):
                gate.decide(current, ("1.0.0", 2), "client")

    def test_server_dependency_edit_does_not_release(self) -> None:
        first = gate.parse('[project]\nversion = "1.0.0"\ndependencies = []', "server")
        second = gate.parse('[project]\nversion = "1.0.0"\ndependencies = ["fastapi"]', "server")
        self.assertFalse(gate.decide(second, first, "server"))
        self.assertTrue(gate.decide(("1.0.1", 0), first, "server"))
        with self.assertRaises(ValueError):
            gate.decide(("0.9.0", 0), first, "server")

    def test_invalid_manifest_versions_are_rejected(self) -> None:
        for version in ("1.0.0", "1.0.0+0", "1.0.0+2100000001", "latest"):
            with self.assertRaises(ValueError):
                gate.parse(f"version: {version}", "client")

    def test_release_endpoints_require_public_https_origins(self) -> None:
        good = {
            "PAPYRUS_API_BASE_URL": "https://api.papyrusreader.org",
            "POWERSYNC_SERVICE_URL": "https://sync.papyrusreader.org",
        }
        gate.validate_endpoints(good)
        for value in (
            "",
            "http://api.papyrusreader.org",
            "https://localhost",
            "https://127.0.0.1",
            "https://192.168.1.2",
            "https://api.example.invalid",
            "https://api.example.com",
            "https://api.papyrusreader.org/v1",
            "https://user:secret@api.papyrusreader.org",
            "https://api.papyrusreader.org?token=x",
        ):
            with self.subTest(value=value), self.assertRaises(ValueError):
                gate.validate_endpoints({**good, "PAPYRUS_API_BASE_URL": value})


class CommittedGateTest(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.command("init", "-q")
        (self.root / "app").mkdir()
        self.manifest = self.root / "app/pubspec.yaml"
        self.manifest.write_text("version: 1.0.0+1\n")
        self.commit()
        self.base = self.command("rev-parse", "HEAD")

    def command(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(self.root), *args], text=True, stderr=subprocess.DEVNULL
        ).strip()

    def commit(self) -> None:
        self.command("add", ".")
        self.command(
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-qm",
            "fixture",
        )

    def run_gate(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(GATE_PATH), "client", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def test_compares_committed_values_and_skips_dependency_edits(self) -> None:
        self.manifest.write_text("version: 1.0.0+1\ndependencies: changed\n")
        self.commit()
        result = self.run_gate("--base", self.base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("release=false", result.stdout)
        self.manifest.write_text("version: 1.0.0+2\n")
        self.commit()
        result = self.run_gate("--base", self.base)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tag=v1.0.0+2", result.stdout)
        self.assertIn("release=true", result.stdout)

    def test_released_tag_cannot_be_reused_for_another_commit(self) -> None:
        self.command("tag", "v1.0.0+1")
        self.manifest.write_text("version: 1.0.0+1\ndependencies: changed\n")
        self.commit()
        result = self.run_gate("--manual")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already belongs to another commit", result.stderr)

    def test_bootstrap_requires_explicit_manual_build(self) -> None:
        self.assertNotEqual(self.run_gate("--base", "0" * 40).returncode, 0)
        self.assertEqual(self.run_gate("--manual").returncode, 0)


if __name__ == "__main__":
    unittest.main()
