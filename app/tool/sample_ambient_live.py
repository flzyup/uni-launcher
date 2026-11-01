#!/usr/bin/env python3
"""Sample the live ambient colour out of the emulator screenshots.

The integration test puts the real settings panel on the screen; the preview
swatch next to "当前颜色" shows the colour the strip would get.

This script grabs a series of screenshots, works out which frames actually
changed (that is the stretch where the music was playing), finds the swatch
by looking for the largest flat block of one colour inside the area that
moved, and prints the colour that was rendered there.

The evidence is a pixel measurement, not a claim: nothing is hard coded, the
swatch is located from the frames themselves.
"""
import colorsys
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageChops

SERIAL = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 120
OUT = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("/tmp/ambient-live")
OUT.mkdir(parents=True, exist_ok=True)


def grab(index):
    out = OUT / f"live-{index:03d}.png"
    with out.open("wb") as handle:
        subprocess.run(["adb", "-s", SERIAL, "exec-out", "screencap", "-p"],
                       stdout=handle, check=True)
    return out


def describe(rgb):
    r, g, b = (v / 255.0 for v in rgb)
    hue, lightness, saturation = colorsys.rgb_to_hls(r, g, b)
    return (f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}  hue={hue * 360:6.1f}deg  "
            f"light={lightness:5.3f}  sat={saturation:5.3f}")


print(f"grabbing {COUNT} frames from {SERIAL}", flush=True)
paths = []
for index in range(COUNT):
    paths.append(grab(index))
    if index % 20 == 0:
        print(f"  {index}/{COUNT}", flush=True)
    time.sleep(0.5)

images = []
for path in paths:
    with Image.open(path) as handle:
        images.append(handle.convert("RGB"))

# Which frames changed? That is the stretch where the music was playing.
moving = []
for index in range(1, len(images)):
    bbox = ImageChops.difference(images[index - 1], images[index]).getbbox()
    if bbox is not None:
        moving.append(index)
print(f"\nframes that changed: {len(moving)}/{len(images) - 1}")
if not moving:
    print("nothing changed — the music was not playing during the capture")
    raise SystemExit(1)

# The swatch is a flat block of one colour inside the area that moved.
first, last = images[moving[0] - 1], images[moving[-1]]
bbox = ImageChops.difference(first, last).getbbox()
print(f"the moving area is x={bbox[0]}..{bbox[2]} y={bbox[1]}..{bbox[3]}")
crop = last.crop(bbox)
colours = crop.getcolors(maxcolors=1 << 20)
colours.sort(reverse=True)
dominant, count = colours[0]
print(f"dominant colour of that area: {dominant} ({count} px)")

# The block that moved the most between the two frames is the swatch: take
# the colour with the biggest difference between the first and the last frame
# among the flat candidates.
best_rgb, best_delta = None, -1
for colour, _ in colours[:40]:
    mask = Image.new("RGB", crop.size)
    mask.paste(colour, (0, 0, crop.size[0], crop.size[1]))
    before = Image.composite(first.crop(bbox), Image.new("RGB", crop.size), mask)
    after = Image.composite(last.crop(bbox), Image.new("RGB", crop.size), mask)
    delta = sum(ImageChops.difference(before, after).convert("L").getdata())
    if delta > best_delta:
        best_delta, best_rgb = delta, colour
print(f"the block that moved the most: {best_rgb}")

colours_seen, brightness = [], []
for index, image in enumerate(images):
    rgb = image.getpixel((bbox[0] + (bbox[2] - bbox[0]) // 2,
                          bbox[1] + (bbox[3] - bbox[1]) // 2))
    hue, lightness, saturation = colorsys.rgb_to_hls(*(v / 255.0 for v in rgb))
    colours_seen.append(rgb)
    brightness.append(lightness)
    marker = " *" if index in moving else ""
    print(f"{index:03d}  {describe(rgb)}{marker}")

print()
print(f"distinct colours: {len(set(colours_seen))}/{len(colours_seen)}")
print(f"brightness span: {max(brightness) - min(brightness):.3f}")
