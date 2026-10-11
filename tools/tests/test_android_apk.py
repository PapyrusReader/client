"""Validate APK identity and enforce explicit signing configuration."""

import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from package_android_apk import check_identity, package


class AndroidApkTest(unittest.TestCase):
    def test_package_and_version_must_match_release(self):
        check_identity("package: name='com.papyrus.reader' versionCode='3' versionName='0.0.3'", "v0.0.3+3")

        for badging in [
            "package: name='com.other.app' versionCode='3' versionName='0.0.3'",
            "package: name='com.papyrus.reader' versionCode='2' versionName='0.0.3'",
            "package: name='com.papyrus.reader' versionCode='3' versionName='0.0.2'",
            "malformed",
        ]:
            with self.subTest(badging=badging), self.assertRaisesRegex(ValueError, "package or version"):
                check_identity(badging, "v0.0.3+3")

    def test_missing_key_cannot_fall_back_to_debug_signing(self):
        with patch.dict(os.environ, {}, clear=True), patch("package_android_apk.subprocess.run") as run:
            with self.assertRaisesRegex(ValueError, "upload key"):
                package(Path('app.aab'), Path('bundletool.jar'), Path('tools'), Path('output'), 'v0.0.3+3')

            run.assert_not_called()
