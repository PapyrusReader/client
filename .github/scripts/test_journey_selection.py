import subprocess
import unittest
from pathlib import Path


class JourneySelectionTest(unittest.TestCase):
    def test_pull_request_job_selection(self):
        toolbar = "app/lib/widgets/shared/app_page_bar.dart"
        upload = "app/lib/powersync/papyrus_powersync_connector.dart"
        reader = "app/lib/reader/reader_bookmark_button.dart"
        gestures = "app/patrol_test/reader_gestures_test.dart"
        cases = [
            ([gestures], "full", False, False),
            ([gestures, toolbar, upload], "full", True, True),
            ([reader, gestures], "full", False, False),
            ([toolbar], "navigation", False, True),
            ([upload], "none", True, False),
            ([toolbar, upload], "navigation", True, True),
            ([toolbar, reader], "pr", False, True),
            ([reader, toolbar], "pr", False, True),
            (["app/lib/data/data_store.dart"], "pr", True, True),
            (["app/pubspec.lock"], "pr", True, True),
            (["app/lib/pages/notes_page.dart"], "pr", True, False),
            (["tools/test_browser_history.py"], "none", False, True),
            (["app/test/pages/book_edit_page_layout_test.dart"], "none", False, False),
        ]
        for paths, android, sync, history in cases:
            with self.subTest(paths=paths):
                output = subprocess.check_output(
                    ["bash", Path(__file__).with_name("select_journeys.sh")],
                    input="\0".join(paths) + "\0",
                    text=True,
                )
                self.assertEqual(
                    dict(line.split("=") for line in output.splitlines()),
                    {"android": android, "sync": str(sync).lower(), "history": str(history).lower()},
                )
