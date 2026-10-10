"""Validate the ELF boundary before invoking the external SquashFS extractor."""

import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from extract_appimage import filesystem_offset


class AppImageExtractionTest(unittest.TestCase):
    def test_type_two_offset_and_corrupt_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tool.AppImage"
            header = bytearray(64)
            header[:6] = b"\x7fELF\x02\x01"
            header[8:11] = b"AI\x02"
            struct.pack_into("<Q", header, 40, 64)
            struct.pack_into("<HH", header, 58, 64, 1)
            source.write_bytes(header + bytes(64) + b"hsqs")
            self.assertEqual(filesystem_offset(source), 128)
            source.write_bytes(header + bytes(64) + b"nope")

            with self.assertRaisesRegex(ValueError, "SquashFS"):
                filesystem_offset(source)

    def test_unrecognized_runtime_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "tool.AppImage"
            source.write_bytes(b"not an AppImage")

            with self.assertRaises(ValueError):
                filesystem_offset(source)
