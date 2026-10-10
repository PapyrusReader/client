"""Run an instrumented desktop package and require its explicit test report."""

import argparse
import json
import os
import subprocess
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    args.report = args.report.resolve()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.unlink(missing_ok=True)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    environment = {**os.environ, "PAPYRUS_SMOKE_REPORT": str(args.report)}
    subprocess.run(command, env=environment, timeout=300, check=True)
    report = json.loads(args.report.read_text())

    if report.get("passed") is not True or not report.get("results"):
        raise ValueError(f"Packaged reader validation did not pass: {report}")

    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
