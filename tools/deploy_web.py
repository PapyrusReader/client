"""Send a verified release to the host's restricted web deployment command."""

import argparse
import os
import subprocess
import tempfile
from pathlib import Path

from release_assets import verify


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    metadata = verify(args.root, args.tag, args.revision)
    settings = {
        name: os.environ.get(name, "")
        for name in (
            "WEB_SSH_HOST",
            "WEB_SSH_USER",
            "WEB_SSH_KNOWN_HOSTS",
            "WEB_SSH_PRIVATE_KEY",
        )
    }

    if not all(settings.values()):
        raise ValueError("Configure WEB_SSH_HOST, WEB_SSH_USER, WEB_SSH_KNOWN_HOSTS and WEB_SSH_PRIVATE_KEY")

    asset = metadata["assets"]["web"]

    with tempfile.TemporaryDirectory() as directory:
        key = Path(directory) / "key"
        key.write_text(settings["WEB_SSH_PRIVATE_KEY"] + "\n")
        key.chmod(0o600)
        known_hosts = Path(directory) / "known_hosts"
        known_hosts.write_text(settings["WEB_SSH_KNOWN_HOSTS"] + "\n")
        target = f"{settings['WEB_SSH_USER']}@{settings['WEB_SSH_HOST']}"
        command = f"deploy {args.revision} {asset['sha256']} {args.tag}"

        with (args.root / asset["name"]).open("rb") as archive:
            subprocess.run(
                [
                    "ssh",
                    "-i",
                    str(key),
                    "-o",
                    "IdentitiesOnly=yes",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "ConnectTimeout=15",
                    "-o",
                    "StrictHostKeyChecking=yes",
                    "-o",
                    f"UserKnownHostsFile={known_hosts}",
                    "--",
                    target,
                    command,
                ],
                stdin=archive,
                check=True,
            )


if __name__ == "__main__":
    main()
