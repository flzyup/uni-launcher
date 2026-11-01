#!/usr/bin/env python3
"""Measure the ambient colour and brightness straight off the emulator screen.

The integration test drives the ambience with a synthetic spectrum and reads
the **rendered pixels** out of the layer tree. This script is the second,
independent channel: it watches the **physical emulator display** and samples
the colour swatch and the brightness bar straight off the screen.

Both channels have to agree. That is what makes the evidence a measurement
instead of a claim:

* the test measures the pixels the engine drew (inside the app);
* this script measures the pixels the emulator actually shows (outside the
  app, through the framebuffer).

## How the swatch is found

The preview card holds three things in the live colour: the **swatch** (a
square), the **brightness bar** (a wide, thin bar) and the **spectrum
strip** (many thin bars). They share the colour, so the colour alone does
not locate the swatch.

The swatch is the only **small square** (40..90 px on a side) that is filled
with **one single colour** in the top left of the screen. The scan looks for
a square of one colour and takes the colour of its middle.

A frame that does not contain the preview simply has no such square and is
skipped, so the build phase and the launcher frames drop out on their own.

Usage:
    python3 tool/sample_ambient_screen.py [serial] [seconds] [outdir]
    python3 tool/sample_ambient_screen.py --from <dir>     # analyse old frames
"""
import colorsys
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

from PIL import Image

SERIAL = "emulator-5554"
SECONDS = 40
OUT = Path("/tmp/ambient-screen")

if "--from" not in sys.argv:
    SERIAL = sys.argv[1] if len(sys.argv) > 1 else "emulator-5554"
    SECONDS = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    OUT = Path(sys.argv[3]) if len(sys.argv) > 3 else Path("/tmp/ambient-screen")
    OUT.mkdir(parents=True, exist_ok=True)


def grab(index):
    path = OUT / f"screen-{index:03d}.png"
    with path.open("wb") as handle:
        subprocess.run(["adb", "-s", SERIAL, "exec-out", "screencap", "-p"],
                       stdout=handle, check=True)
    return path


def describe(rgb):
    r, g, b = (v / 255.0 for v in rgb)
    hue, lightness, saturation = colorsys.rgb_to_hls(r, g, b)
    return (f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}  hue={hue * 360:6.1f}deg  "
            f"light={lightness:5.3f}  sat={saturation:5.3f}")


def find_swatch(image):
    """Finds the colour swatch of the preview.

    Returns ``(colour, box)`` where ``box`` is the swatch rectangle, or
    ``(None, None)`` when the preview is not on screen.
    """
    region = image.crop((0, 0, min(300, image.width), min(200, image.height)))
    pixels = region.load()
    rw, rh = region.size
    # The colours of the region, most used first: the swatch colour is one
    # of them, and the swatch is a square of exactly that colour.
    colours = region.getcolors(maxcolors=1 << 20)
    colours.sort(reverse=True)
    for entry in colours:
        count, colour = entry
        if count < 800:
            continue
        # Collect the horizontal runs of this colour and look for a stack of
        # them that all start and end at the same x — that is a square.
        runs_by_row = []
        for y in range(rh):
            x = 0
            row_runs = []
            while x < rw:
                if pixels[x, y] != colour:
                    x += 1
                    continue
                start = x
                while x < rw and pixels[x, y] == colour:
                    x += 1
                row_runs.append((start, x - start))
            runs_by_row.append(row_runs)
        for y in range(rh):
            for start, run in runs_by_row[y]:
                if run < 40 or run > 90:
                    continue
                # How many rows below have a run of the same width at the
                # same x? A square has that many.
                height = 0
                for iy in range(y, min(y + run + 4, rh)):
                    if any(s == start and r >= run - 2
                           for s, r in runs_by_row[iy]):
                        height += 1
                    else:
                        break
                if height < run - 4 or height > run + 4:
                    continue
                # The middle of the square is the live colour.
                cx = start + run // 2
                cy = y + height // 2
                if cx >= rw or cy >= rh:
                    continue
                inner = pixels[cx, cy]
                if inner == colour:
                    return inner, (start, y, start + run, y + height)
    return None, None


def measure_bar(image, swatch_colour, swatch_box):
    """Measures the filled width of the brightness bar.

    The bar sits right under the swatch and is drawn in the same colour, so
    the longest run of that colour on a row below the swatch is the
    brightness on the glass.
    """
    width, height = image.size
    if swatch_box is None:
        return 0, 0
    best = 0
    for y in range(swatch_box[3] + 2, min(swatch_box[3] + 26, height)):
        row = [image.getpixel((x, y)) for x in range(width)]
        run = 0
        for x in range(width):
            px = row[x]
            if (abs(px[0] - swatch_colour[0]) <= 8
                    and abs(px[1] - swatch_colour[1]) <= 8
                    and abs(px[2] - swatch_colour[2]) <= 8):
                run += 1
                if run > best:
                    best = run
            else:
                run = 0
    return best, width


def analyse(paths):
    """Measures every frame and prints the result."""
    samples = []
    for path in paths:
        with Image.open(path) as handle:
            image = handle.convert("RGB")
        colour, box = find_swatch(image)
        if colour is None:
            continue
        filled, total = measure_bar(image, colour, box)
        samples.append((path.name, colour, filled, total, box))

    print(f"\nframes with a readable swatch: {len(samples)}/{len(paths)}")
    if not samples:
        raise SystemExit("no swatch found — the preview was not on screen")

    seen, luma = [], []
    for name, colour, filled, total, box in samples:
        seen.append(colour)
        luma.append(sum(colour))
        print(f"{name}  {describe(colour)}  bar={filled}/{total}px  box={box}")

    print()
    print(f"distinct colours: {len(set(seen))}/{len(seen)}")
    print(f"luma span: {min(luma)} .. {max(luma)}")
    fills = [s[2] for s in samples]
    if fills:
        print(f"bar fill span: {min(fills)} .. {max(fills)} px")


if __name__ == "__main__":
    if "--from" in sys.argv:
        directory = Path(sys.argv[sys.argv.index("--from") + 1])
        analyse(sorted(directory.glob("screen-*.png")))
    else:
        print(f"grabbing the screen of {SERIAL} for {SECONDS}s", flush=True)
        paths = []
        index = 0
        deadline = time.time() + SECONDS
        while time.time() < deadline:
            paths.append(grab(index))
            index += 1
            if index % 10 == 0:
                print(f"  {index} frames", flush=True)
        analyse(paths)
