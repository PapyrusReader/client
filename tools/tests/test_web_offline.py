"""Offline web packaging must be complete, deterministic, and versioned."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_web_offline import prepare


class OfflinePackagingTest(unittest.TestCase):
    def test_revision_changes_with_assets_and_worker_but_not_repeated_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("index.html", "flutter_bootstrap.js", "main.dart.js", "folder_access.js", "app_updates.js", "book_worker.js"):
                (root / name).write_text(name)
            worker = root / "papyrus_service_worker.js"
            worker.write_text("const applicationRevision = 'unprepared';\n")
            (root / "main.dart.js.map").write_text("debug information")
            first = prepare(root)
            self.assertEqual(prepare(root), first)
            self.assertNotIn("main.dart.js.map", first["assets"])
            self.assertNotIn("offline-manifest.json", first["assets"])
            self.assertIn("book_worker.js", first["assets"])
            self.assertIn(first["revision"], worker.read_text())
            (root / "main.dart.js").write_text("updated application")
            second = prepare(root)
            self.assertNotEqual(first["revision"], second["revision"])
            worker.write_text(worker.read_text() + "// updated caching behavior\n")
            self.assertNotEqual(prepare(root)["revision"], second["revision"])

    def test_partial_build_cannot_be_packaged_for_offline_use(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "Missing web application asset"):
                prepare(Path(directory))
