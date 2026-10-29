import unittest

from summarize_test_timing import summarize


class TestTimingTest(unittest.TestCase):
    def test_overlapping_tests_do_not_inflate_elapsed_and_failures_are_ranked(self):
        report = summarize([
            {"type": "testStart", "time": 0, "test": {"id": 1, "name": "slow"}},
            {"type": "testStart", "time": 1000, "test": {"id": 2, "name": "failed | case"}},
            {"type": "testDone", "time": 3000, "testID": 2, "result": "failure"},
            {"type": "testDone", "time": 4000, "testID": 1, "result": "success"},
            {"type": "done", "time": 4500},
        ])
        self.assertIn("Test reporter elapsed: 4.50s (complete report)", report)
        self.assertIn("| 2.00 | failure | failed \\| case |", report)
        self.assertLess(report.index("| 4.00"), report.index("| 2.00"))

    def test_partial_reports_exclude_skipped_hidden_and_unfinished_tests(self):
        events = []

        for test_id, name in enumerate(["skipped case", "hidden load", "unfinished"]):
            events.append({"type": "testStart", "time": 0, "test": {"id": test_id, "name": name}})

        events.extend([
            {"type": "testDone", "time": 100, "testID": 0, "skipped": True},
            {"type": "testDone", "time": 200, "testID": 1, "hidden": True},
        ])
        report = summarize(events)
        self.assertIn("0.20s (partial report)", report)
        self.assertNotIn("skipped case", report)
        self.assertNotIn("hidden load", report)
        self.assertNotIn("unfinished", report)


if __name__ == "__main__":
    unittest.main()
