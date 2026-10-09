"""Preserve Flutter runtime skips when converting JSON with junitreport 2.0.2.

The converter only recognizes a non-null testStart.metadata.skipReason, while
Flutter also reports skips at testDone (for example, markTestSkipped at runtime).
Keep the raw report unchanged; normalize only the copy supplied to the converter.
"""

import json
import sys
from pathlib import Path


def normalize_skips(events):
    skipped_ids = {
        event["testID"]
        for event in events
        if event["type"] == "testDone" and event.get("skipped") is True
    }
    for event in events:
        if event["type"] == "testStart" and event["test"]["id"] in skipped_ids:
            test = event["test"]
            metadata = test.get("metadata", {})
            if metadata.get("skipReason") is None:
                event = {
                    **event,
                    "test": {
                        **test,
                        "metadata": {
                            **metadata,
                            "skipReason": "Skipped by the test runner",
                        },
                    },
                }
        yield event


if __name__ == "__main__":
    source, destination = map(Path, sys.argv[1:])
    events = [
        json.loads(line)
        for line in source.read_text(encoding="utf-8").splitlines()
        if line
    ]
    destination.write_text(
        "".join(json.dumps(event) + "\n" for event in normalize_skips(events)),
        encoding="utf-8",
    )
