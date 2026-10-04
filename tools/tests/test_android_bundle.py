"""Exercise the native-library check without requiring an Android build."""

import importlib.util
import struct
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("android_bundle", Path(__file__).resolve().parents[1] / "check_android_bundle.py")
assert spec is not None and spec.loader is not None
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class AlignmentTest(unittest.TestCase):
    def elf(self, alignment: int, offset: int = 0) -> bytes:
        identity = b"\x7fELF\x02\x01" + bytes(10)
        header = struct.pack("<16sHHIQQQIHHHHHH", identity, 3, 183, 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0)
        return header + struct.pack("<IIQQQQQQ", 1, 0, offset, 0, 0, 1, 1, alignment)

    def test_accepts_16kb_and_64kb(self) -> None:
        for alignment in (16384, 65536):
            bundle.check_elf(self.elf(alignment), "lib.so")

    def test_rejects_4kb_and_incongruent_offsets(self) -> None:
        for alignment, offset in ((4096, 0), (16384, 4096)):
            with self.assertRaises(ValueError):
                bundle.check_elf(self.elf(alignment, offset), "lib.so")
