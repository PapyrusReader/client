"""Prepare a Flutter web build for offline startup and local book import."""

import argparse
import hashlib
import json
import re
from pathlib import Path


def prepare(root: Path) -> dict:
    required = ("index.html", "flutter_bootstrap.js", "main.dart.js", "folder_access.js", "auth_landing.js", "app_updates.js", "book_worker.js", "papyrus_service_worker.js")

    for name in required:
        if not (root / name).is_file():
            raise ValueError(f"Missing web application asset: {name}")

    excluded = {"offline-manifest.json", "papyrus_service_worker.js", "flutter_service_worker.js"}
    assets = sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name not in excluded and path.suffix not in {".map", ".symbols"}
    )
    worker = root / "papyrus_service_worker.js"
    source = re.sub(r"const applicationRevision = '[^']*';", "const applicationRevision = 'unprepared';", worker.read_text())
    checksum = hashlib.sha256(source.encode())

    for name in assets:
        checksum.update(name.encode())
        checksum.update(hashlib.sha256((root / name).read_bytes()).digest())

    manifest = {"revision": checksum.hexdigest(), "assets": assets}
    (root / "offline-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    worker.write_text(source.replace("const applicationRevision = 'unprepared';", f"const applicationRevision = '{manifest['revision']}';"))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    prepare(parser.parse_args().root)
