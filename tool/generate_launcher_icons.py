#!/usr/bin/env python3
"""Render the original NexaPOS SVG into platform launcher assets.

This optional asset-maintenance tool requires Pillow. It does not run during
Flutter builds. Its small SVG renderer accepts only this mark's rounded
rectangles, so no external artwork, font, network or SVG engine is required.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/nexapos-launcher.svg"
PROVENANCE = ROOT / "assets/branding/PROVENANCE.json"
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
WINDOWS_SIZES = (16, 24, 32, 48, 64, 128, 256)


def render(size):
    """Supersample original SVG geometry for clean small launcher pixels."""
    source = ET.fromstring(SOURCE.read_bytes())
    assert source.get("viewBox") == "0 0 512 512"
    scale = size * 4 / 512
    image = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for item in source:
        tag = item.tag.rsplit("}", 1)[-1]
        if tag in ("title", "desc"):
            continue
        if tag != "rect":
            raise ValueError(f"Unsupported original mark geometry: {tag}")
        x, y, width, height, radius = (float(item.get(key, "0")) * scale
                                      for key in ("x", "y", "width", "height", "rx"))
        draw.rounded_rectangle((x, y, x + width, y + height),
                               radius=radius, fill=item.get("fill"))
    return image.resize((size, size), Image.Resampling.LANCZOS)


def png(size):
    output = io.BytesIO()
    render(size).save(output, format="PNG", optimize=False)
    return output.getvalue()


def ico():
    """Store an explicit PNG frame for every Windows shell icon size."""
    frames = [png(size) for size in WINDOWS_SIZES]
    offset = 6 + 16 * len(frames)
    directory = bytearray(struct.pack("<HHH", 0, 1, len(frames)))
    for size, frame in zip(WINDOWS_SIZES, frames):
        dimension = 0 if size == 256 else size
        directory.extend(struct.pack("<BBBBHHII", dimension, dimension, 0, 0,
                                     1, 32, len(frame), offset))
        offset += len(frame)
    return bytes(directory) + b"".join(frames)


def expected_assets():
    assets = {}
    for density, size in SIZES.items():
        path = f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        assets[path] = png(size)
    assets["windows/runner/resources/app_icon.ico"] = ico()
    return assets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="Verify committed pixels and provenance without writing")
    args = parser.parse_args()
    assets = expected_assets()
    manifest = {
        "source": "assets/branding/nexapos-launcher.svg",
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "authorship": "Original NexaPOS geometric artwork; no third-party image or glyph copied.",
        "identity": "BrandMark POS-terminal concept; AppBrand primary #2563eb and secondary #0d9488.",
        "generator": "tool/generate_launcher_icons.py (Pillow 12.3.0)",
        "assets": {path: hashlib.sha256(data).hexdigest()
                   for path, data in sorted(assets.items())},
        "windows_sizes": list(WINDOWS_SIZES),
        "android_sizes": SIZES,
    }
    if args.check:
        assert json.loads(PROVENANCE.read_text()) == manifest, "Launcher provenance differs"
        for path, expected in assets.items():
            assert (ROOT / path).read_bytes() == expected, f"Launcher pixels differ: {path}"
        print("Five Android launcher densities and seven Windows icon frames match the original SVG.")
        return
    for path, data in assets.items():
        (ROOT / path).write_bytes(data)
    PROVENANCE.write_text(json.dumps(manifest, indent=2) + "\n")
    print("Generated five Android launcher densities and seven Windows icon frames.")


if __name__ == "__main__":
    main()
