import copy
import unittest

from normalize_test_report import normalize_skips


class NormalizeSkipsTest(unittest.TestCase):
    def test_uses_final_skip_status_without_changing_raw_events(self):
        events = [
            {"type": "testStart", "test": {"id": 1, "metadata": {"skip": False}}},
            {"type": "testStart", "test": {"id": 2, "metadata": {"skip": True}}},
            {"type": "testStart", "test": {"id": 3, "metadata": {"skip": False}}},
            {"type": "testDone", "testID": 1, "skipped": True},
            {"type": "testDone", "testID": 2, "skipped": True},
            {"type": "testDone", "testID": 3, "skipped": False},
        ]
        original = copy.deepcopy(events)
        normalized = list(normalize_skips(events))
        self.assertIsNotNone(normalized[0]["test"]["metadata"]["skipReason"])
        self.assertIsNotNone(normalized[1]["test"]["metadata"]["skipReason"])
        self.assertEqual(normalized[2:], original[2:])
        self.assertEqual(events, original)

    def test_preserves_existing_skip_reason_and_hidden_events(self):
        events = [
            {
                "type": "testStart",
                "test": {"id": 1, "metadata": {"skipReason": "Missing fixture"}},
            },
            {"type": "testDone", "testID": 1, "skipped": True, "hidden": True},
        ]
        self.assertEqual(list(normalize_skips(events)), events)


if __name__ == "__main__":
    unittest.main()
