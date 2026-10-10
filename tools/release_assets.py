"""Package, verify and publish immutable client release assets."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from release_gate import parse

TAG = re.compile(r"v([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)")


def identity(tag: str, revision: str) -> dict:
    match = TAG.fullmatch(tag)

    if not match or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Expected a client release tag and full Git commit SHA")

    return {"tag": tag, "version": match[1], "build_number": int(match[2]), "revision": revision}


def names(tag: str) -> dict[str, str]:
    if not TAG.fullmatch(tag):
        raise ValueError("Invalid release tag")

    return {
        "android": f"papyrus-{tag}-android-universal.aab",
        "web": f"papyrus-{tag}-web.zip",
        "linux_archive": f"papyrus-{tag}-linux-x64.tar.gz",
        "deb": f"papyrus-{tag}-linux-x64.deb",
        "appimage": f"papyrus-{tag}-linux-x64.AppImage",
        "windows_archive": f"papyrus-{tag}-windows-x64.zip",
        "installer": f"papyrus-{tag}-windows-x64-setup.exe",
        "instructions": f"papyrus-{tag}-INSTALL.md",
    }


def digest(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def seal(root: Path, tag: str, revision: str) -> dict:
    metadata = identity(tag, revision)
    files = names(tag)

    if {path.name for path in root.iterdir()} != set(files.values()):
        raise ValueError("Release must contain exactly the expected assets")

    metadata["assets"] = {key: {"name": name, "sha256": digest(root / name)} for key, name in files.items()}
    (root / "release-manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    checksums = [f"{digest(path)}  {path.name}\n" for path in sorted(root.iterdir())]
    (root / "SHA256SUMS").write_text("".join(checksums))
    return metadata


def verify(root: Path, tag: str, revision: str) -> dict:
    expected = identity(tag, revision)
    metadata = json.loads((root / "release-manifest.json").read_text())

    if any(metadata.get(key) != value for key, value in expected.items()):
        raise ValueError("Artifact identity does not match the release tag and commit")

    files = names(tag)

    if set(metadata["assets"]) != set(files):
        raise ValueError("Unexpected release assets")

    for key, name in files.items():
        entry = metadata["assets"][key]

        if entry != {"name": name, "sha256": digest(root / name)}:
            raise ValueError(f"Release asset checksum mismatch: {name}")

    expected_files = set(files.values()) | {"release-manifest.json"}

    if {path.name for path in root.iterdir()} != expected_files | {"SHA256SUMS"}:
        raise ValueError("Missing or unexpected files in release")

    checksums = "".join(f"{digest(root / name)}  {name}\n" for name in sorted(expected_files))

    if (root / "SHA256SUMS").read_text() != checksums:
        raise ValueError("Release checksum index mismatch")

    return metadata


def gh(*args: str) -> str:
    return subprocess.check_output(["gh", *args], text=True).strip()


def tag_commit(tag: str) -> str:
    if not TAG.fullmatch(tag):
        raise ValueError("Invalid release tag")

    subprocess.run(["git", "fetch", "origin", f"refs/tags/{tag}:refs/tags/{tag}"], check=True)
    revision = subprocess.check_output(["git", "rev-parse", f"{tag}^{{commit}}"], text=True).strip()
    source = subprocess.check_output(["git", "show", f"{revision}:app/pubspec.yaml"], text=True)
    version, number = parse(source, "client")

    if tag != f"v{version}+{number}":
        raise ValueError("Release tag does not match its committed app version")

    return revision


def download(root: Path, tag: str) -> dict:
    revision = tag_commit(tag)
    release = json.loads(gh("release", "view", tag, "--json", "isDraft,isPrerelease"))

    if release["isDraft"] or release["isPrerelease"]:
        raise ValueError("Delivery requires a published, non-prerelease GitHub release")

    root.mkdir(parents=True, exist_ok=True)
    gh("release", "download", tag, "--dir", str(root))
    return verify(root, tag, revision)


def publish(root: Path, tag: str, revision: str) -> None:
    verify(root, tag, revision)
    existing = subprocess.run(["gh", "release", "view", tag, "--json", "isDraft"], capture_output=True, text=True)

    if existing.returncode == 0:
        if tag_commit(tag) != revision:
            raise ValueError("Release tag belongs to another commit")

        with tempfile.TemporaryDirectory() as directory:
            previous = Path(directory)
            gh("release", "download", tag, "--dir", str(previous))
            verify(previous, tag, revision)

            if any(digest(path) != digest(previous / path.name) for path in root.iterdir()):
                raise ValueError("Published assets differ; create a new build number instead of overwriting")

        if json.loads(existing.stdout)["isDraft"]:
            gh("release", "edit", tag, "--draft=false")

        return

    gh(
        "release",
        "create",
        tag,
        "--target",
        revision,
        "--title",
        f"Papyrus {tag}",
        "--draft",
        "--generate-notes",
        *[str(path) for path in sorted(root.iterdir())],
    )
    gh("release", "edit", tag, "--draft=false")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("stamp-web", "seal", "verify", "download", "publish"))
    parser.add_argument("root", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--revision", default=os.environ.get("GITHUB_SHA", ""))
    args = parser.parse_args()

    if args.command == "stamp-web":
        (args.root / "release.json").write_text(json.dumps(identity(args.tag, args.revision), indent=2) + "\n")
    elif args.command == "seal":
        instructions = Path(__file__).resolve().parents[1] / "docs/INSTALL.md"
        shutil.copyfile(instructions, args.root / names(args.tag)["instructions"])
        seal(args.root, args.tag, args.revision)
    elif args.command == "verify":
        verify(args.root, args.tag, args.revision)
    elif args.command == "download":
        metadata = download(args.root, args.tag)

        if os.environ.get("GITHUB_OUTPUT"):
            with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
                output.write(f"revision={metadata['revision']}\n")

    else:
        publish(args.root, args.tag, args.revision)


if __name__ == "__main__":
    main()
