"""Create and validate a signed universal APK from the release's existing AAB."""

import argparse
import os
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path

from check_android_bundle import check
from release_assets import TAG, names


def check_identity(badging: str, tag: str) -> None:
    version = TAG.fullmatch(tag)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.MULTILINE)

    if not version or not package or package.groups() != ("com.papyrus.reader", version[2], version[1]):
        raise ValueError("APK package or version does not match the release")


def package(bundle: Path, bundletool: Path, build_tools: Path, output: Path, tag: str) -> None:
    variables = ["ANDROID_KEYSTORE_PATH", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD"]

    if any(not os.environ.get(name) for name in variables):
        raise ValueError("APK packaging requires the release upload key. Debug signing is not permitted.")

    apk_name = names(tag)["android_apk"]
    output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)
        store_password = temporary / "store-password"
        key_password = temporary / "key-password"

        for path, variable in [(store_password, "ANDROID_KEYSTORE_PASSWORD"), (key_password, "ANDROID_KEY_PASSWORD")]:
            path.touch(mode=0o600)
            path.write_text(os.environ[variable])

        archive = temporary / "universal.apks"
        subprocess.run([
            "java", "-jar", str(bundletool), "build-apks", f"--bundle={bundle}", f"--output={archive}",
            "--mode=universal", f"--ks={os.environ['ANDROID_KEYSTORE_PATH']}",
            f"--ks-key-alias={os.environ['ANDROID_KEY_ALIAS']}",
            f"--ks-pass=file:{store_password}", f"--key-pass=file:{key_password}",
        ], check=True)
        apk = temporary / apk_name

        with zipfile.ZipFile(archive) as artifacts:
            apk.write_bytes(artifacts.read("universal.apk"))

        subprocess.run([str(build_tools / "apksigner"), "verify", str(apk)], check=True)
        subprocess.run([str(build_tools / "zipalign"), "-c", "-P", "16", "4", str(apk)], check=True)
        badging = subprocess.check_output([str(build_tools / "aapt2"), "dump", "badging", str(apk)], text=True)
        check_identity(badging, tag)
        check(apk)
        (output / apk_name).write_bytes(apk.read_bytes())

    print(f"Verified signed APK: {apk_name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--bundletool", type=Path, required=True)
    parser.add_argument("--build-tools", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    package(args.bundle, args.bundletool, args.build_tools, args.output, args.tag)


if __name__ == "__main__":
    main()
