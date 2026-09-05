"""Regenerate the iOS app icon set from the LabDesk mark in res/icon.png.

Run from the repository root:

    python flutter/tool/make_ios_app_icons.py

res/icon.png is a rounded tile with transparent corners, which is right for a
tray icon and wrong for iOS: the App Store rejects a marketing icon with an
alpha channel, and iOS applies its own corner mask, so a pre-rounded icon shows
a second, darker rounding inside the first. Every file written here is a square
opaque RGB image with no alpha.

The transparent corners are filled from the icon itself rather than from a flat
colour, because the tile carries a lighter sweep across its top left and a flat
fill would show a seam there. The artwork is grown outwards one pixel at a time
until the corners are covered, so each corner takes the colour of the artwork
next to it and no edge appears. Growing has to reach about 0.29 * radius, the
depth of the corner arc along the diagonal.
"""

from pathlib import Path

from PIL import Image, ImageChops

# The sizes Contents.json asks for, as point size times scale.
SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

GROW_PIXELS = 96

SOURCE = Path("res/icon.png")
TARGET = Path("flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset")


def square_opaque(source: Path) -> Image.Image:
    icon = Image.open(source).convert("RGBA")
    # The rounded edge is anti-aliased, and replicating a half-transparent pixel
    # outwards draws a streak. Only fully opaque artwork is allowed to grow.
    solid = icon.copy()
    solid.putalpha(icon.getchannel("A").point(lambda a: 255 if a == 255 else 0))
    grown = solid
    for _ in range(GROW_PIXELS):
        for offset in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grown = Image.alpha_composite(ImageChops.offset(grown, *offset), grown)
    if grown.getchannel("A").getextrema()[0] != 255:
        raise SystemExit("the corners are still transparent; raise GROW_PIXELS")
    return grown.convert("RGB")


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"{SOURCE} not found; run this from the repository root")
    master = square_opaque(SOURCE)
    for name, size in sorted(SIZES.items()):
        out = TARGET / name
        master.resize((size, size), Image.LANCZOS).save(out, "PNG")
        print(f"{out} {size}x{size}")


if __name__ == "__main__":
    main()
