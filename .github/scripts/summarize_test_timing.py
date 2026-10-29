"""Summarize Flutter JSON reporter timings without treating overlapping tests as wall time."""

import json
import sys
from pathlib import Path


def summarize(events):
    starts = {}
    durations = []
    elapsed = 0
    complete = False

    for event in events:
        elapsed = max(elapsed, event.get("time", 0))

        if event["type"] == "testStart":
            starts[event["test"]["id"]] = (event["test"]["name"], event["time"])
        elif event["type"] == "testDone":
            start = starts.pop(event["testID"], None)

            if start and not event.get("hidden") and not event.get("skipped"):
                name, begin = start
                durations.append((event["time"] - begin, name, event.get("result", "unknown")))
        elif event["type"] == "done":
            complete = True

    state = "complete" if complete else "partial"
    lines = [
        "### Flutter test durations",
        "",
        f"Test reporter elapsed: {elapsed / 1000:.2f}s ({state} report).",
        "This excludes work before reporter startup, such as browser compilation. Use job timings for the full CI cost.",
        "Durations include per-test setup/teardown. Tests can overlap, so their sum is not elapsed or runner time.",
        "Skipped and hidden runner events are excluded from the ranking.",
        "",
        "| Seconds | Result | Test |",
        "| ---: | --- | --- |",
    ]

    for duration, name, result in sorted(durations, reverse=True)[:20]:
        name = name.replace("|", "\\|").replace("\n", " ").replace("`", "'")
        lines.append(f"| {duration / 1000:.2f} | {result} | {name} |")

    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    with Path(sys.argv[1]).open(encoding="utf-8") as source:
        print(summarize(json.loads(line) for line in source if line.strip()), end="")
