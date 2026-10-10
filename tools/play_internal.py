"""Inspect Play before upload; safely finish an interrupted internal-track delivery."""

import argparse
import json
import os
import urllib.request
from pathlib import Path

from release_assets import verify

PACKAGE = "com.papyrus.reader"
BASE = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}/edits"


def request(method: str, path: str, body: dict | None = None) -> dict:
    token = os.environ["PLAY_ACCESS_TOKEN"]
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    with urllib.request.urlopen(
        urllib.request.Request(BASE + path, data=data, headers=headers, method=method), timeout=60
    ) as response:
        content = response.read()
        return json.loads(content) if content else {}


def inspect(bundles: list[dict], tracks: list[dict], number: int, checksum: str) -> str:
    numbers = [int(bundle["versionCode"]) for bundle in bundles]
    numbers += [
        int(code)
        for track in tracks
        for release in track.get("releases", [])
        for code in release.get("versionCodes", [])
    ]

    if any(code > number for code in numbers):
        raise ValueError("Play already contains a newer version; refusing to deliver an older build")

    matching = [bundle for bundle in bundles if int(bundle["versionCode"]) == number]

    if not matching:
        if number in numbers:
            raise ValueError("Version exists on a track but its bundle identity could not be verified")

        return "upload"

    if len(matching) != 1 or matching[0].get("sha256", "").lower() != checksum:
        raise ValueError("Play bundle checksum differs from the GitHub release")

    internal = next((track for track in tracks if track["track"] == "internal"), {})

    if any(
        release.get("status") == "completed" and release.get("versionCodes") == [str(number)]
        for release in internal.get("releases", [])
    ):
        return "complete"

    return "promote"


def preflight(metadata: dict, *, recover: bool = True) -> str:
    edit = request("POST", "", {})["id"]

    try:
        bundles = request("GET", f"/{edit}/bundles").get("bundles", [])
        tracks = request("GET", f"/{edit}/tracks").get("tracks", [])
        result = inspect(bundles, tracks, metadata["build_number"], metadata["assets"]["android"]["sha256"])

        if result == "promote" and recover:
            request(
                "PUT",
                f"/{edit}/tracks/internal",
                {
                    "track": "internal",
                    "releases": [
                        {
                            "name": metadata["tag"],
                            "versionCodes": [str(metadata["build_number"])],
                            "status": "completed",
                        }
                    ],
                },
            )
            request("POST", f"/{edit}:commit", {})
            edit = ""
            return "complete"

        return result
    finally:
        if edit:
            request("DELETE", f"/{edit}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--verify-delivered", action="store_true")
    args = parser.parse_args()
    metadata = verify(args.root, args.tag, args.revision)

    # Use the service account's own key, without IAM impersonation privileges.
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    credentials = service_account.Credentials.from_service_account_info(
        json.loads(os.environ["PLAY_SERVICE_ACCOUNT_JSON"]),
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    credentials.refresh(Request())
    os.environ["PLAY_ACCESS_TOKEN"] = credentials.token
    result = preflight(metadata, recover=not args.verify_delivered)

    if args.verify_delivered and result != "complete":
        raise ValueError("Play internal delivery was not confirmed")

    if os.environ.get("GITHUB_OUTPUT"):
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
            output.write(f"upload={str(result == 'upload').lower()}\n")

    print(f"Play internal: {result}")


if __name__ == "__main__":
    main()
