"""Exercise signed APT metadata and publication as a complete release asset set."""

import gzip
import hashlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import apt_repository as apt
import release_assets as assets

TAG = "v0.2.0+7"


class AptMetadataTest(unittest.TestCase):
    def test_index_binds_package_identity_size_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / assets.names(TAG)["deb"]
            package.write_bytes(b"package bytes")
            control = "Package: papyrus\nVersion: 0.2.0-7\nArchitecture: amd64\nDescription: reader\n"

            with patch.object(apt.subprocess, "check_output", return_value=control):
                index = apt.package_index(package, "0.2.0", 7).decode()
                self.assertIn(f"SHA256: {hashlib.sha256(package.read_bytes()).hexdigest()}", index)
                self.assertIn(f"Filename: {package.name}", index)

                with self.assertRaisesRegex(ValueError, "identity"):
                    apt.package_index(package, "0.2.0", 8)

    def test_partial_repository_cannot_be_sealed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            for name in assets.names(TAG).values():
                (root / name).write_bytes(b"asset")

            (root / "InRelease").write_text("partial")

            with self.assertRaisesRegex(ValueError, "together"):
                assets.seal(root, TAG, "a" * 40)

    def test_repository_assets_are_covered_by_release_verification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            for name in [*assets.names(TAG).values(), *apt.APT_FILES.values()]:
                (root / name).write_bytes(b"asset")

            assets.seal(root, TAG, "a" * 40)
            assets.verify(root, TAG, "a" * 40)
            (root / "InRelease").write_bytes(b"tampered")

            with self.assertRaisesRegex(ValueError, "checksum"):
                assets.verify(root, TAG, "a" * 40)

    def test_missing_signing_material_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "signing"):
            apt.build(Path("unused"), TAG, "", "")


@unittest.skipUnless(shutil.which("gpg") and shutil.which("dpkg-deb"), "APT integration requires GPG and dpkg")
class AptSigningTest(unittest.TestCase):
    def test_real_signature_and_package_index(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "gnupg"
            home.mkdir(mode=0o700)
            gpg = ["gpg", "--homedir", str(home), "--batch", "--pinentry-mode", "loopback", "--passphrase", ""]
            subprocess.run(
                [*gpg, "--quick-generate-key", "Papyrus test <test@example.invalid>", "ed25519", "sign", "1d"],
                check=True, capture_output=True,
            )
            listing = subprocess.check_output([*gpg, "--with-colons", "--list-keys"], text=True, stderr=subprocess.DEVNULL)
            fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
            private_key = subprocess.check_output([*gpg, "--armor", "--export-secret-keys", fingerprint], text=True)
            package_root = root / "package"
            (package_root / "DEBIAN").mkdir(parents=True)
            (package_root / "DEBIAN/control").write_text(
                "Package: papyrus\nVersion: 0.2.0-7\nArchitecture: amd64\n"
                "Maintainer: Test <test@example.invalid>\nDescription: test package\n"
            )
            repository = root / "repository"
            repository.mkdir()
            subprocess.run(
                ["dpkg-deb", "--build", str(package_root), str(repository / assets.names(TAG)["deb"])],
                check=True, capture_output=True,
            )
            apt.build(repository, TAG, private_key, fingerprint)
            subprocess.run(
                ["gpgv", "--keyring", str(repository / "papyrus-archive-keyring.gpg"), str(repository / "InRelease")],
                check=True, capture_output=True,
            )
            index = gzip.decompress((repository / "Packages.gz").read_bytes()).decode()
            self.assertIn("Version: 0.2.0-7", index)

            # Use APT itself with isolated lists/cache to prove the flat feed is consumable.
            if shutil.which("apt-get"):
                (root / "lists/partial").mkdir(parents=True)
                (root / "cache/archives/partial").mkdir(parents=True)
                source = root / "papyrus.list"
                source.write_text(
                    f"deb [signed-by={repository}/papyrus-archive-keyring.gpg] file:{repository} ./\n"
                )
                command = [
                    "apt-get", "-o", f"Dir::Etc::sourcelist={source}", "-o", "Dir::Etc::sourceparts=-",
                    "-o", f"Dir::State::lists={root}/lists", "-o", f"Dir::Cache={root}/cache",
                    "-o", "APT::Sandbox::User=root",
                ]
                result = subprocess.run([*command, "update"], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                update_output = result.stdout + result.stderr
                result = subprocess.run([*command, "download", "papyrus=0.2.0-7"], cwd=root, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, update_output + result.stdout + result.stderr)
                self.assertTrue((root / "papyrus_0.2.0-7_amd64.deb").exists())

            (repository / "InRelease").write_bytes((repository / "InRelease").read_bytes().replace(b"PapyrusReader", b"OtherReader!!"))
            result = subprocess.run(
                ["gpgv", "--keyring", str(repository / "papyrus-archive-keyring.gpg"), str(repository / "InRelease")],
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
