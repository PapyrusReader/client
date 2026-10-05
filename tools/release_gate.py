"""Decide releases from committed versions, not file changes or workflow counters."""

import argparse
import ipaddress
import os
import re
import subprocess
import tomllib
from collections.abc import Mapping
from pathlib import Path
from urllib.parse import urlsplit


def parse(text: str, component: str) -> tuple[str, int]:
    if component == "client":
        match = re.search(r"^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", text, re.M)
        if not match:
            raise ValueError("pubspec version must be MAJOR.MINOR.PATCH+BUILD")
        version, number = match.groups()
        if not 0 < int(number) <= 2100000000:
            raise ValueError("Android build number must be between 1 and 2100000000")
        return version, int(number)
    version = str(tomllib.loads(text)["project"]["version"])
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Server version must be MAJOR.MINOR.PATCH")
    return version, 0


def decide(current: tuple[str, int], previous: tuple[str, int], component: str, *, published: bool = True) -> bool:
    if current == previous:
        return False
    if not published:
        return True
    if tuple(map(int, current[0].split("."))) < tuple(map(int, previous[0].split("."))):
        raise ValueError("Release version cannot decrease")
    if component == "client" and current[1] <= previous[1]:
        raise ValueError("Every Android release must increase the committed build number")
    return True


def validate_endpoints(environ: Mapping[str, str]) -> None:
    for key in ("PAPYRUS_API_BASE_URL", "POWERSYNC_SERVICE_URL"):
        value = environ.get(key, "")
        uri = urlsplit(value)
        host = uri.hostname or ""
        if uri.scheme != "https" or not host or uri.username or uri.password or uri.query or uri.fragment:
            raise ValueError(f"{key} must be a public HTTPS base URL without credentials, query or fragment")
        if uri.path not in ("", "/"):
            raise ValueError(f"{key} must be the origin URL; the client adds /v1 itself")
        if (
            host == "localhost"
            or host.endswith((".localhost", ".local", ".invalid", ".test", ".example.com"))
            or host == "example.com"
        ):
            raise ValueError(f"{key} must not point to a development host")
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            continue
        if not address.is_global:
            raise ValueError(f"{key} must not point to a private IP address")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=("client", "server"))
    parser.add_argument("--base")
    parser.add_argument("--manual", action="store_true")
    parser.add_argument("--endpoints", action="store_true")
    args = parser.parse_args()
    if args.endpoints:
        validate_endpoints(os.environ)
        return
    path = "app/pubspec.yaml" if args.component == "client" else "pyproject.toml"
    current = parse(git("show", f"HEAD:{path}"), args.component)
    if args.manual:
        release = True
    elif args.base and set(args.base) != {"0"}:
        published = bool(git("tag", "--list", "v[0-9]*"))
        release = decide(
            current, parse(git("show", f"{args.base}:{path}"), args.component), args.component, published=published
        )
    else:
        raise ValueError("A previous commit is required; use a manual build to bootstrap")
    version, number = current
    tag = f"v{version}+{number}" if args.component == "client" else f"v{version}"
    existing = subprocess.run(
        ["git", "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}"], capture_output=True, text=True
    )
    if release and existing.returncode == 0 and existing.stdout.strip() != git("rev-parse", "HEAD"):
        raise ValueError(f"{tag} already belongs to another commit; bump the version")
    output = f"release={str(release).lower()}\nversion={version}\nbuild_number={number}\ntag={tag}\n"
    if os.environ.get("GITHUB_OUTPUT"):
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as file:
            file.write(output)
    print(output, end="")


if __name__ == "__main__":
    main()
