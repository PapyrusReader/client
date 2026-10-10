"""Extract a type-2 x64 AppImage without FUSE or executing its ELF runtime."""

import argparse
import struct
import subprocess
from pathlib import Path


def filesystem_offset(source: Path) -> int:
    with source.open("rb") as stream:
        header = stream.read(64)

        if len(header) != 64 or header[:4] != b"\x7fELF" or header[4:6] != b"\x02\x01" or header[8:11] != b"AI\x02":
            raise ValueError("Expected a little-endian ELF64 type-2 AppImage")

        section_offset = struct.unpack_from("<Q", header, 40)[0]
        section_size, section_count = struct.unpack_from("<HH", header, 58)
        offset = section_offset + section_size * section_count
        stream.seek(offset)

        if stream.read(4) != b"hsqs":
            raise ValueError("Expected SquashFS immediately after the ELF runtime")

        return offset


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()
    subprocess.run(
        [
            "unsquashfs",
            "-quiet",
            "-offset",
            str(filesystem_offset(args.source)),
            "-dest",
            str(args.target),
            str(args.source),
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
