"""Reject 64-bit native ELF libraries that cannot load on Android 16 KB pages."""

import struct
import sys
import zipfile
from pathlib import Path


def check_elf(data: bytes, name: str) -> None:
    if data[:5] != b"\x7fELF\x02":
        raise ValueError(f"{name}: expected a 64-bit ELF library")
    order = "<" if data[5] == 1 else ">"
    header = struct.unpack_from(order + "16sHHIQQQIHHHHHH", data)
    offset, size, count = header[5], header[9], header[10]
    for index in range(count):
        segment = struct.unpack_from(order + "IIQQQQQQ", data, offset + size * index)
        kind, _, file_offset, address, _, _, _, alignment = segment
        if kind == 1 and (alignment < 16384 or file_offset % 16384 != address % 16384):
            raise ValueError(f"{name}: LOAD segment is not 16 KB aligned (alignment={alignment})")


def check(path: Path) -> None:
    count = 0
    with zipfile.ZipFile(path) as bundle:
        for name in bundle.namelist():
            if name.endswith(".so") and ("/arm64-v8a/" in name or "/x86_64/" in name):
                check_elf(bundle.read(name), name)
                count += 1
    if count == 0:
        raise ValueError("No 64-bit native libraries found in the bundle")
    print(f"Verified 16 KB ELF alignment of {count} native libraries. Device and APK packaging checks remain required.")


if __name__ == "__main__":
    check(Path(sys.argv[1]))
