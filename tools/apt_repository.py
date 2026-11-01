"""Build a signed flat APT repository alongside immutable GitHub release downloads."""

import argparse
import datetime
import email.utils
import gzip
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

APT_FILES = {
    "apt_packages": "Packages.gz",
    "apt_packages_plain": "Packages",
    "apt_release": "Release",
    "apt_signature": "Release.gpg",
    "apt_inrelease": "InRelease",
    "apt_key": "papyrus-archive-keyring.gpg",
}


def package_index(package: Path, version: str, number: int) -> bytes:
    control = subprocess.check_output(["dpkg-deb", "--field", str(package)], text=True)
    fields = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line and not line.startswith(" "))

    if (fields.get("Package"), fields.get("Version"), fields.get("Architecture")) != (
        "papyrus", f"{version}-{number}", "amd64"
    ):
        raise ValueError("APT package identity does not match the release")

    if any(name in fields for name in ("Filename", "Size", "SHA256")):
        raise ValueError("Package control cannot override repository metadata")

    checksum = hashlib.sha256(package.read_bytes()).hexdigest()
    return (
        control.rstrip() + f"\nFilename: {package.name}\nSize: {package.stat().st_size}\nSHA256: {checksum}\n\n"
    ).encode()


def release_index(index: bytes, packages: bytes, date: datetime.datetime) -> str:
    return (
        "Origin: PapyrusReader\nLabel: Papyrus\nSuite: stable\nCodename: papyrus\nArchitectures: amd64\n"
        f"Date: {email.utils.format_datetime(date, usegmt=True)}\n"
        f"SHA256:\n {hashlib.sha256(index).hexdigest()} {len(index)} Packages\n"
        f" {hashlib.sha256(packages).hexdigest()} {len(packages)} Packages.gz\n"
    )


def build(root: Path, tag: str, private_key: str, fingerprint: str) -> None:
    from release_assets import TAG, names
    import re

    match = TAG.fullmatch(tag)

    if not match or not re.fullmatch(r"[A-Fa-f0-9]{40}", fingerprint) or not private_key.strip():
        raise ValueError("APT publishing requires a release tag, signing key and full signing-key fingerprint")

    package = root / names(tag)["deb"]
    index = package_index(package, match[1], int(match[2]))
    compressed = gzip.compress(index, mtime=0)
    (root / "Packages").write_bytes(index)
    (root / "Packages.gz").write_bytes(compressed)
    date = datetime.datetime.now(datetime.timezone.utc)
    (root / "Release").write_text(release_index(index, compressed, date))

    with tempfile.TemporaryDirectory() as directory:
        home = Path(directory)
        home.chmod(0o700)
        command = ["gpg", "--homedir", str(home), "--batch", "--yes"]
        subprocess.run([*command, "--import"], input=private_key.encode(), capture_output=True, check=True)
        key = subprocess.check_output([*command, "--export", fingerprint])

        if not key:
            raise ValueError("APT signing fingerprint does not identify the imported key")

        (root / "papyrus-archive-keyring.gpg").write_bytes(key)

        for output, operation in [("InRelease", "--clearsign"), ("Release.gpg", "--detach-sign")]:
            subprocess.run([
                *command, "--local-user", fingerprint, "--digest-algo", "SHA256", "--output", str(root / output),
                operation, str(root / "Release"),
            ], check=True, capture_output=True)

        subprocess.run([
            *command, "--verify", str(root / "Release.gpg"), str(root / "Release"),
        ], check=True, capture_output=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    build(args.root, args.tag, os.environ.get("APT_SIGNING_KEY", ""), os.environ.get("APT_SIGNING_FINGERPRINT", ""))


if __name__ == "__main__":
    main()
