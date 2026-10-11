"""Regression tests for release identity, Play retries and transactional web delivery."""

import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release_assets as assets
import play_internal as play

if os.name != "nt":
    import install_web as web

TAG = "v0.0.2+2"
REVISION = "a" * 40


class ReleaseAssetsTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

        for name in assets.names(TAG).values():
            (self.root / name).write_bytes(name.encode())

        assets.seal(self.root, TAG, REVISION)

    def test_complete_release_roundtrip(self):
        self.assertEqual(assets.verify(self.root, TAG, REVISION)["build_number"], 2)

    def test_changed_asset_and_checksum_index_rejected(self):
        (self.root / assets.names(TAG)["android"]).write_bytes(b"changed")

        with self.assertRaisesRegex(ValueError, "checksum"):
            assets.verify(self.root, TAG, REVISION)

    def test_new_release_requires_apk_and_checks_its_checksum(self):
        apk = self.root / assets.names(TAG)["android_apk"]
        apk.write_bytes(b"changed")

        with self.assertRaisesRegex(ValueError, "checksum"):
            assets.verify(self.root, TAG, REVISION)

        apk.unlink()
        (self.root / "release-manifest.json").unlink()
        (self.root / "SHA256SUMS").unlink()

        with self.assertRaisesRegex(ValueError, "expected assets"):
            assets.seal(self.root, TAG, REVISION)

    def test_published_aab_only_release_remains_verifiable(self):
        manifest = self.root / "release-manifest.json"
        metadata = json.loads(manifest.read_text())
        (self.root / metadata["assets"].pop("android_apk")["name"]).unlink()
        manifest.write_text(json.dumps(metadata, indent=2) + "\n")
        files = sorted(path for path in self.root.iterdir() if path.name != "SHA256SUMS")
        (self.root / "SHA256SUMS").write_text("".join(f"{assets.digest(path)}  {path.name}\n" for path in files))
        self.assertEqual(assets.verify(self.root, TAG, REVISION), metadata)

    def test_wrong_commit_rejected(self):
        with self.assertRaisesRegex(ValueError, "identity"):
            assets.verify(self.root, TAG, "b" * 40)

    def test_checksum_index_alone_cannot_be_changed(self):
        (self.root / "SHA256SUMS").write_text("0" * 64 + "  release-manifest.json\n")

        with self.assertRaisesRegex(ValueError, "checksum index"):
            assets.verify(self.root, TAG, REVISION)

    def test_manifest_cannot_choose_a_path(self):
        manifest = self.root / "release-manifest.json"
        data = json.loads(manifest.read_text())
        data["assets"]["web"]["name"] = "../outside.zip"
        manifest.write_text(json.dumps(data))

        with self.assertRaises(ValueError):
            assets.verify(self.root, TAG, REVISION)

    def test_invalid_tag_rejected(self):
        for tag in ("../../test", "v0.0.2", "v0.0.2+0", "--help", "v0.0.2+2\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                assets.names(tag)

    def test_tag_must_match_committed_version(self):
        with (
            patch.object(assets.subprocess, "run"),
            patch.object(assets.subprocess, "check_output", side_effect=[REVISION, "version: 0.0.3+3\n"]),
            self.assertRaisesRegex(ValueError, "committed app version"),
        ):
            assets.tag_commit(TAG)

    def test_existing_release_never_overwritten(self):
        previous = assets.digest(self.root / "SHA256SUMS")

        def fake_gh(*args):
            if args[:2] == ("release", "download"):
                target = Path(args[-1])

                for path in self.root.iterdir():
                    (target / path.name).write_bytes(path.read_bytes())

                return ""

            self.fail(f"Unexpected mutation: {args}")

        with (
            patch.object(assets.subprocess, "run") as run,
            patch.object(assets, "tag_commit", return_value=REVISION),
            patch.object(assets, "gh", side_effect=fake_gh),
        ):
            run.return_value.returncode = 0
            run.return_value.stdout = '{"isDraft": false}'
            assets.publish(self.root, TAG, REVISION)

        self.assertEqual(assets.digest(self.root / "SHA256SUMS"), previous)


class PlayRetryTest(unittest.TestCase):
    def test_new_upload(self):
        self.assertEqual(play.inspect([], [], 2, "abc"), "upload")

    def test_matching_upload_can_be_promoted(self):
        self.assertEqual(play.inspect([{"versionCode": 2, "sha256": "abc"}], [], 2, "abc"), "promote")

    def test_matching_completed_release_is_noop(self):
        tracks = [{"track": "internal", "releases": [{"status": "completed", "versionCodes": ["2"]}]}]
        self.assertEqual(play.inspect([{"versionCode": 2, "sha256": "abc"}], tracks, 2, "abc"), "complete")

    def test_conflicting_or_older_upload_rejected(self):
        for bundles in ([{"versionCode": 2, "sha256": "different"}], [{"versionCode": 3, "sha256": "abc"}]):
            with self.assertRaises(ValueError):
                play.inspect(bundles, [], 2, "abc")

    def test_newer_version_on_another_track_rejected(self):
        with self.assertRaises(ValueError):
            play.inspect([], [{"track": "production", "releases": [{"versionCodes": ["3"]}]}], 2, "abc")

    def test_recovery_only_updates_internal_track(self):
        metadata = {"tag": TAG, "build_number": 2, "assets": {"android": {"sha256": "abc"}}}
        replies = [{"id": "edit"}, {"bundles": [{"versionCode": 2, "sha256": "abc"}]}, {"tracks": []}, {}, {}]

        with patch.object(play, "request", side_effect=replies) as request:
            self.assertEqual(play.preflight(metadata), "complete")

        self.assertEqual(request.call_args_list[3].args[0:2], ("PUT", "/edit/tracks/internal"))
        self.assertEqual(request.call_args_list[4].args[0:2], ("POST", "/edit:commit"))

    def test_final_verification_does_not_modify_a_track(self):
        metadata = {"tag": TAG, "build_number": 2, "assets": {"android": {"sha256": "abc"}}}
        replies = [{"id": "edit"}, {"bundles": [{"versionCode": 2, "sha256": "abc"}]}, {"tracks": []}, {}]

        with patch.object(play, "request", side_effect=replies) as request:
            self.assertEqual(play.preflight(metadata, recover=False), "promote")

        self.assertEqual([call.args[0] for call in request.call_args_list], ["POST", "GET", "GET", "DELETE"])


@unittest.skipIf(os.name == "nt", "Host deployment uses POSIX file locks and symlinks")
class WebDeploymentTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name) / "web"
        (self.root / "releases/initial").mkdir(parents=True)
        (self.root / "releases/initial/index.html").write_text("previous")
        (self.root / "current").symlink_to("releases/initial")
        self.archive = Path(directory.name) / "release.zip"
        self.metadata = assets.identity(TAG, REVISION)
        self.create_archive()

    def create_archive(self, extra=None):
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name in web.REQUIRED:
                value = json.dumps(self.metadata) if name == "release.json" else name
                archive.writestr(name, value)

            if extra:
                archive.writestr(*extra)

        self.checksum = hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def install(self, probe=lambda *_: None):
        web.install(self.archive, self.root, REVISION, self.checksum, TAG, probe)

    def test_activate_retry_and_preserve_previous(self):
        self.install()
        self.install()
        self.assertEqual(os.readlink(self.root / "current"), f"releases/{REVISION}")
        self.assertEqual(os.readlink(self.root / "previous"), "releases/initial")
        self.assertEqual((self.root / "previous/index.html").read_text(), "previous")

    def public_response(self, request, timeout):
        route = request.full_url.split("?", 1)[0].removeprefix("https://app.example.com")
        filename = "index.html" if route in ("/", "/login") else route.removeprefix("/")
        response = io.BytesIO((self.root / "current" / filename).read_bytes())
        response.headers = {"Cache-Control": "no-cache"}
        return response

    def test_public_probe_checks_entrypoints_and_compiled_app(self):
        self.install()

        with patch.object(web.urllib.request, "urlopen", side_effect=self.public_response) as request:
            web.verify_public("https://app.example.com", self.metadata, self.root / "current")

        routes = [call.args[0].full_url for call in request.call_args_list]
        self.assertEqual(len(routes), 5)
        self.assertIn("https://app.example.com/main.dart.js", routes)

    def test_cdn_cache_override_rolls_back_release(self):
        def response(request, timeout):
            result = self.public_response(request, timeout)

            if request.full_url.endswith("/flutter_bootstrap.js"):
                result.headers["Cache-Control"] = "max-age=14400"

            return result

        with patch.object(web.urllib.request, "urlopen", side_effect=response), patch.object(web.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "must revalidate"):
                self.install(lambda metadata, release: web.verify_public("https://app.example.com", metadata, release))

        self.assertEqual(os.readlink(self.root / "current"), "releases/initial")

    def test_stale_compiled_app_rolls_back_release(self):
        def response(request, timeout):
            result = self.public_response(request, timeout)

            if request.full_url.endswith("/main.dart.js"):
                result = io.BytesIO(b"previous compiled app")
                result.headers = {"Cache-Control": "no-cache"}

            return result

        with patch.object(web.urllib.request, "urlopen", side_effect=response), patch.object(web.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.install(lambda metadata, release: web.verify_public("https://app.example.com", metadata, release))

        self.assertEqual(os.readlink(self.root / "current"), "releases/initial")

    def test_older_build_is_rejected_without_activation(self):
        self.install()
        self.metadata = assets.identity("v0.0.1+1", "b" * 40)
        self.create_archive()

        with self.assertRaisesRegex(ValueError, "older web build"):
            web.install(self.archive, self.root, "b" * 40, self.checksum, "v0.0.1+1", lambda *_: self.fail())

        self.assertEqual(os.readlink(self.root / "current"), f"releases/{REVISION}")
        self.assertEqual(os.readlink(self.root / "previous"), "releases/initial")

    def test_same_build_cannot_change_release_identity(self):
        self.install()
        self.metadata = assets.identity(TAG, "b" * 40)
        self.create_archive()

        with self.assertRaisesRegex(ValueError, "different release identity"):
            web.install(self.archive, self.root, "b" * 40, self.checksum, TAG, lambda *_: self.fail())

        self.assertEqual(os.readlink(self.root / "current"), f"releases/{REVISION}")

    def test_invalid_active_build_number_fails_closed(self):
        self.install()
        metadata = {**self.metadata, "build_number": "2"}
        (self.root / "current/release.json").write_text(json.dumps(metadata))

        with self.assertRaisesRegex(ValueError, "metadata is invalid"):
            self.install()

    def test_published_release_requires_active_metadata(self):
        self.install()
        (self.root / "current/release.json").unlink()

        with self.assertRaisesRegex(ValueError, "metadata is missing"):
            self.install()

    def test_newer_build_can_replace_active_release(self):
        self.install()
        self.metadata = assets.identity("v0.0.3+3", "b" * 40)
        self.create_archive()
        web.install(self.archive, self.root, "b" * 40, self.checksum, "v0.0.3+3", lambda *_: None)
        self.assertEqual(os.readlink(self.root / "current"), f"releases/{'b' * 40}")
        self.assertEqual(os.readlink(self.root / "previous"), f"releases/{REVISION}")

    def test_failed_public_probe_restores_previous(self):
        def fail(*_):
            raise ValueError("public mismatch")

        with self.assertRaisesRegex(ValueError, "public mismatch"):
            self.install(fail)

        self.assertEqual(os.readlink(self.root / "current"), "releases/initial")

    def test_checksum_and_metadata_fail_before_activation(self):
        self.checksum = "0" * 64

        with self.assertRaisesRegex(ValueError, "checksum"):
            self.install()

        self.metadata["build_number"] = 3
        self.create_archive()

        with self.assertRaisesRegex(ValueError, "metadata"):
            self.install()

        self.assertEqual(os.readlink(self.root / "current"), "releases/initial")

    def test_unsafe_zip_entries_rejected(self):
        for name in ("../escape", "/absolute", "directory/../../escape", "directory\\escape", "index.html"):
            with self.subTest(name=name):
                self.create_archive((name, "bad"))

                with self.assertRaisesRegex(ValueError, "unsafe"):
                    self.install()

    def test_symlink_rejected(self):
        entry = zipfile.ZipInfo("link")
        entry.create_system = 3
        entry.external_attr = 0o120777 << 16
        self.create_archive((entry, "../../escape"))

        with self.assertRaisesRegex(ValueError, "unsafe"):
            self.install()

    def test_same_revision_cannot_change_contents(self):
        self.install()
        self.create_archive(("extra.txt", "different"))

        with self.assertRaisesRegex(ValueError, "different contents"):
            self.install()


if __name__ == "__main__":
    unittest.main()
