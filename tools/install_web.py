"""Receive a web release over restricted SSH, activate it and roll back failed probes."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import stat
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_BYTES = 2 * 1024 * 1024 * 1024
REQUIRED = ("index.html", "flutter_bootstrap.js", "main.dart.js", "release.json")


def extract(archive: Path, target: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()

        if sum(entry.file_size for entry in entries) > MAX_EXPANDED_BYTES:
            raise ValueError("Web archive is too large")

        seen = set()

        for entry in entries:
            path = Path(entry.filename)
            mode = entry.external_attr >> 16

            if (
                path.is_absolute()
                or ".." in path.parts
                or "\\" in entry.filename
                or path in seen
                or stat.S_ISLNK(mode)
                or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR))
            ):
                raise ValueError("Web archive contains an unsafe or duplicate entry")

            seen.add(path)

        source.extractall(target)

    for name in REQUIRED:
        if not (target / name).is_file():
            raise ValueError(f"Web archive is missing {name}")

    for path in [target, *target.rglob("*")]:
        path.chmod(0o755 if path.is_dir() else 0o644)


def activate(root: Path, target: str) -> None:
    link = root / ".current-next"
    link.unlink(missing_ok=True)
    link.symlink_to(target)
    os.replace(link, root / "current")


def verify_public(url: str, metadata: dict, release: Path) -> None:
    for attempt in range(5):
        try:
            for route, filename in (
                ("/release.json", "release.json"),
                ("/", "index.html"),
                ("/login", "index.html"),
                ("/flutter_bootstrap.js", "flutter_bootstrap.js"),
                ("/main.dart.js", "main.dart.js"),
            ):
                request = urllib.request.Request(
                    f"{url}{route}",
                    headers={
                        "User-Agent": "PapyrusReleaseVerifier/1.0 (+https://github.com/PapyrusReader/client)",
                    },
                )

                with urllib.request.urlopen(request, timeout=10) as response:
                    directives = {value.strip().lower() for value in response.headers.get("Cache-Control", "").split(",")}

                    if not directives.intersection({"no-cache", "no-store"}):
                        raise ValueError(f"Public web content must revalidate before reuse: {route}")

                    if response.read() != (release / filename).read_bytes():
                        raise ValueError(f"Public web content does not match the release: {route}")

            return
        except (OSError, ValueError):
            if attempt == 4:
                raise

            time.sleep(2)


def install(archive: Path, root: Path, revision: str, checksum: str, tag: str, probe) -> None:
    match = re.fullmatch(r"v([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)", tag)

    if not match or not re.fullmatch(r"[0-9a-f]{40}", revision) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ValueError("Invalid release identity")

    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
        raise ValueError("Web archive checksum mismatch")

    releases = root / "releases"
    releases.mkdir(parents=True, exist_ok=True)

    with (root / ".deployment.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        staging = Path(tempfile.mkdtemp(prefix=".staging-", dir=releases))

        try:
            extract(archive, staging)
            metadata = json.loads((staging / "release.json").read_text())
            expected = {"revision": revision, "tag": tag, "version": match[1], "build_number": int(match[2])}

            if metadata != expected:
                raise ValueError("Web metadata does not match the requested release")

            current = root / "current"

            if not current.is_symlink():
                raise ValueError("Migrate the existing web directory before enabling delivery")

            previous = os.readlink(current)

            if not re.fullmatch(r"releases/[a-zA-Z0-9_-]+", previous) or not current.is_dir():
                raise ValueError("Current web release must be an existing directory inside releases/")

            active_metadata = current / "release.json"

            if active_metadata.exists():
                active = json.loads(active_metadata.read_text())

                if not isinstance(active, dict) or type(active.get("build_number")) is not int:
                    raise ValueError("Active web release metadata is invalid")

                if metadata["build_number"] < active["build_number"]:
                    raise ValueError("Refusing to deploy an older web build; use the operator rollback procedure")

                if metadata["build_number"] == active["build_number"]:
                    if metadata != active:
                        raise ValueError("Active web build has different release identity")

                    if (current / ".artifact-sha256").read_text().strip() != checksum:
                        raise ValueError("Active web build has different contents")
            elif not re.fullmatch(r"releases/initial(?:-[a-zA-Z0-9_-]+)?", previous):
                raise ValueError("Active web release metadata is missing")

            release = releases / revision

            if release.exists():
                if (release / ".artifact-sha256").read_text().strip() != checksum:
                    raise ValueError("Existing web revision has different contents")
            else:
                (staging / ".artifact-sha256").write_text(checksum + "\n")
                staging.rename(release)

            target = f"releases/{revision}"
            try:
                activate(root, target)
                probe(metadata, release)
            except BaseException:
                activate(root, previous)
                raise

            if previous != target:
                (root / "previous").unlink(missing_ok=True)
                (root / "previous").symlink_to(previous)

            print(f"Verified web release {tag} ({revision})")
        finally:
            if staging.exists():
                shutil.rmtree(staging)


def interrupted(signum, frame) -> None:
    raise InterruptedError("Deployment interrupted")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--public-url", default="https://app.papyrus-reader.com")
    args = parser.parse_args()
    command = shlex.split(os.environ.get("SSH_ORIGINAL_COMMAND", ""))

    if len(command) != 4 or command[0] != "deploy":
        raise ValueError("Only deploy REVISION SHA256 TAG is permitted")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)

    with tempfile.TemporaryDirectory(dir=args.root) as directory:
        archive = Path(directory) / "web.zip"
        received = 0

        with archive.open("wb") as destination:
            while chunk := sys.stdin.buffer.read(1024 * 1024):
                received += len(chunk)

                if received > MAX_ARCHIVE_BYTES:
                    raise ValueError("Web archive exceeds the upload limit")

                destination.write(chunk)

        install(
            archive,
            args.root,
            command[1],
            command[2],
            command[3],
            lambda metadata, release: verify_public(args.public_url, metadata, release),
        )


if __name__ == "__main__":
    main()
