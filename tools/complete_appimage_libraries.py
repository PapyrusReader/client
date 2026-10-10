"""Include non-base dependencies that linuxdeploy's generic exclusion list omits.

The host supplies glibc and graphics-driver ABI libraries. GTK, text shaping,
WebKit and other application dependencies belong in the AppImage even when a
full desktop distribution commonly preinstalls them.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

BASE_LIBRARY = re.compile(
    r"^(?:ld-linux[^/]*|lib(?:c|m|mvec|dl|pthread|rt|resolv|util|anl|BrokenLocale|thread_db|gcc_s|stdc\+\+)"
    r"\.so.*|libnss_(?:compat|dns|files|hesiod)\.so.*|lib(?:GL|EGL|GLX|GLES[^/]*|GLdispatch|drm[^/]*|gbm|vulkan)\.so.*)$"
)


def complete(appdir: Path) -> None:
    library_directory = appdir / "usr/lib"
    environment = {
        **os.environ,
        "LD_LIBRARY_PATH": f"{library_directory}:{appdir / 'usr/bin/lib'}",
    }
    dependencies: dict[str, Path] = {}

    for path in appdir.rglob("*"):
        if not path.is_file():
            continue

        with path.open("rb") as source:
            if source.read(4) != b"\x7fELF":
                continue

        result = subprocess.run(["ldd", str(path)], env=environment, capture_output=True, text=True, check=True)

        if "=> not found" in result.stdout:
            raise ValueError(f"Unresolved shared libraries in {path}: {result.stdout}")

        for name, location in re.findall(r"^\s*(\S+) => (/\S+) ", result.stdout, re.MULTILINE):
            if not BASE_LIBRARY.fullmatch(name):
                dependencies[name] = Path(location)

    for name, source in sorted(dependencies.items()):
        target = library_directory / name

        if not source.is_relative_to(appdir) and not target.exists():
            shutil.copy2(source, target)
            print(f"Bundled non-base library: {name}")


if __name__ == "__main__":
    complete(Path(sys.argv[1]).resolve())
