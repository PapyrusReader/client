#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.0.0"]
# ///
"""Generate platform icons from the canonical SVG, or validate them with --check.

Requires rsvg-convert (Homebrew librsvg / Debian librsvg2-bin).
Run from the client repository:
    uv run tools/generate_icons.py
    uv run tools/generate_icons.py --check

The canonical emblem is app/assets/images/logo-icon-light.svg (128.41 by
143.18). Square canvases add padding to preserve its proportions. The check
runs in CI and validates artwork, dimensions, Apple catalog slots, web manifest
sizes, opaque iOS backgrounds, Windows ICO frames, installer artwork and mask safe zones.

Android uses 48 dp legacy icons and 108 dp adaptive foregrounds with artwork
inside the central 66 dp safe circle. Web maskable icons use opaque backgrounds
and an 80% diameter safe circle. macOS uses a padded plate. Windows and ordinary
web icons retain transparency. Linux packaging fits the generated
assets/images/logo.png into a 256-pixel square without changing its proportions.
Windows setup uses opaque BMP artwork at four times the classic wizard size:
a 164:314 sidebar and a square header, both generated from the same emblem.

Platform specifications:
    https://developer.android.com/develop/ui/compose/system/icon_design_adaptive
    https://w3c.github.io/manifest/#icon-masks
    https://developer.apple.com/documentation/xcode/configuring-your-app-icon
    https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction
"""

import argparse
import io
import json
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "app"
SOURCE = APP / "assets/images/logo-icon-light.svg"
ANDROID = APP / "android/app/src/main/res"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
WINDOWS_SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)


def render_source():
    result = subprocess.run(
        ["rsvg-convert", "--keep-aspect-ratio", "--height", "2048", str(SOURCE)],
        check=True,
        capture_output=True,
    )

    return Image.open(io.BytesIO(result.stdout)).convert("RGBA")


def icon(source, size, fraction, background=None, macos=False):
    """Fit the non-square emblem uniformly inside a square platform canvas."""
    canvas = Image.new("RGBA", (size, size), background or (0, 0, 0, 0))

    if macos:
        ImageDraw.Draw(canvas).rounded_rectangle(
            (size * 0.1, size * 0.1, size * 0.9, size * 0.9),
            radius=size * 0.18,
            fill="white",
        )

    scale = size * fraction / max(source.size)
    emblem = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )

    canvas.alpha_composite(emblem, ((size - emblem.width) // 2, (size - emblem.height) // 2))
    return canvas.convert("RGB") if background else canvas


def catalog_icons(platform):
    directory = APP / platform / "Runner/Assets.xcassets/AppIcon.appiconset"
    entries = json.loads((directory / "Contents.json").read_text())["images"]

    for entry in entries:
        width, height = map(float, entry["size"].split("x"))
        scale = float(entry["scale"].removesuffix("x"))

        if width != height or not (width * scale).is_integer():
            raise ValueError(f"Invalid square icon slot: {entry}")

        yield directory / entry["filename"], int(width * scale)


def installer_sidebar(source):
    canvas = Image.new("RGB", (656, 1256), "#f4f3fa")
    emblem = icon(source, 440, 0.9)
    canvas.paste(emblem, ((canvas.width - emblem.width) // 2, 300), emblem)
    font = ImageFont.truetype(str(APP / "fonts/MadimiOne-Regular.ttf"), 88)
    ImageDraw.Draw(canvas).text((canvas.width // 2, 790), "Papyrus", font=font, fill="#3e3c8f", anchor="mt")
    return canvas


def outputs(source):
    images = {}

    for density, scale in DENSITIES.items():
        directory = ANDROID / f"mipmap-{density}"
        images[directory / "ic_launcher.png"] = icon(source, int(48 * scale), 0.88)
        # Android uses a 108 dp layer with a central 66 dp safe circle.
        images[directory / "ic_launcher_foreground.png"] = icon(source, int(108 * scale), 64 / 108)

    for path, size in catalog_icons("ios"):
        images[path] = icon(source, size, 0.8, "white")

    for path, size in catalog_icons("macos"):
        # Draw the plate at high resolution so the smallest corners stay smooth.
        images[path] = icon(source, 1024, 0.64, macos=True).resize((size, size), Image.Resampling.LANCZOS)

    for size in (192, 512):
        images[APP / f"web/icons/Icon-{size}.png"] = icon(source, size, 0.9)
        # PWA maskable artwork must fit in a circle of radius 40% of the canvas.
        images[APP / f"web/icons/Icon-maskable-{size}.png"] = icon(source, size, 0.76, "white")

    images[APP / "web/favicon.png"] = icon(source, 32, 0.94)
    images[APP / "assets/images/logo.png"] = source.resize(
        (round(source.width * 1581 / source.height), 1581),
        Image.Resampling.LANCZOS,
    )

    images[ROOT / "packaging/windows/assets/wizard.bmp"] = installer_sidebar(source)
    images[ROOT / "packaging/windows/assets/wizard-small.bmp"] = icon(source, 232, 0.8, "white")

    return images


def check_image(path, actual, expected):
    if actual.size != expected.size or actual.mode != expected.mode:
        raise ValueError(f"{path}: expected {expected.size} {expected.mode}, got {actual.size} {actual.mode}")

    # Allow small antialiasing differences between librsvg versions, not stretching,
    # missing padding, stale artwork, or a different platform's template icon.
    difference = ImageStat.Stat(ImageChops.difference(actual, expected))

    if max(difference.mean) > 0.5:
        raise ValueError(f"{path}: artwork differs from the proportional SVG export")


def check_safe_circle(image, radius):
    pixels = image.convert("RGBA").load()
    transparent = image.mode == "RGBA"

    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]

            if alpha > 127 and (transparent or min(red, green, blue) < 250):
                distance = ((x + 0.5 - image.width / 2) ** 2 + (y + 0.5 - image.height / 2) ** 2) ** 0.5

                if distance > radius:
                    raise ValueError("Emblem extends outside the platform safe circle")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="Validate checked-in assets without writing files")
    args = parser.parse_args()
    source = render_source()
    viewbox = list(map(float, ET.parse(SOURCE).getroot().attrib["viewBox"].split()))

    if abs(source.width / source.height - viewbox[2] / viewbox[3]) > 1 / source.height:
        raise ValueError("SVG rendering changed the original aspect ratio")

    images = outputs(source)

    for path, expected in images.items():
        image = expected

        if args.check:
            with Image.open(path) as actual:
                check_image(path.relative_to(ROOT), actual, expected)
                image = actual.copy()
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            expected.save(path)

        if "foreground" in path.name:
            check_safe_circle(image, image.width * 33 / 108)
        elif "maskable" in path.name:
            check_safe_circle(image, image.width * 0.4)

    manifest = json.loads((APP / "web/manifest.json").read_text())

    for entry in manifest["icons"]:
        size = images[APP / "web" / entry["src"]].size

        if entry["sizes"] != f"{size[0]}x{size[1]}":
            raise ValueError(f"Web manifest size mismatch: {entry}")

    path = APP / "windows/runner/resources/app_icon.ico"
    frames = [icon(source, size, 0.9) for size in WINDOWS_SIZES]

    if args.check:
        with Image.open(path) as actual:
            if actual.ico.sizes() != {(size, size) for size in WINDOWS_SIZES}:
                raise ValueError("Windows ICO is missing required resolutions")

            for frame in frames:
                check_image(path.relative_to(ROOT), actual.ico.getimage(frame.size), frame)
    else:
        frames[-1].save(path, sizes=[frame.size for frame in frames], append_images=frames[:-1])

    print(f"{'Validated' if args.check else 'Generated'} {len(images)} platform images and {len(frames)} Windows ICO frames")


if __name__ == "__main__":
    main()
