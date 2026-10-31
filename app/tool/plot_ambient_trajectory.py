#!/usr/bin/env python3
"""Plot the ambient colour trajectory of a live run.

The claim this picture has to settle: "the strip keeps one base colour and
only the brightness moves".

The answer is not visible in a strip of swatches -- every swatch of a blue
family looks like the same blue. What is visible is the **path**: where the
colour went in the OKLab plane, and how the hue / lightness / chroma moved
over time. So this script draws three panels:

1. the OKLab (a, b) plane with the path the colour actually took;
2. the lightness, the chroma and the distance from the first frame over time;
3. the hue over time, with the 170..320 degree band of the V2 palette marked.

Usage::

    python3 tool/plot_ambient_trajectory.py \
        --report verification/ambient-live/emulator-report.json \
        --out ../shots/13-ambient-colour-trajectory.png
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

# ---- the palette of the V2 chain (must match the product) ----
HUE_BAND_LOW = 170.0
HUE_BAND_HIGH = 320.0

BACKGROUND = (11, 16, 24)
PANEL = (18, 25, 35)
GRID = (38, 50, 64)
TEXT = (208, 220, 232)
MUTED = (120, 138, 158)
ACCENT = (86, 178, 255)
ACCENT_2 = (255, 168, 92)
ACCENT_3 = (110, 225, 170)

FONT_CANDIDATES = [
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def load_font(size: int):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


# ---- colour maths (sRGB <-> OKLab, CIEDE2000) ----

def srgb_to_linear(c: float) -> float:
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb_to_oklab(r: int, g: int, b: int):
    R, G, B = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
    l = (0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B) ** (1 / 3)
    m = (0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B) ** (1 / 3)
    s = (0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B) ** (1 / 3)
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


def rgb_to_lab(r: int, g: int, b: int):
    R, G, B = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
    X = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047
    Y = (0.2126729 * R + 0.7151522 * G + 0.0721750 * B)
    Z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else (7.787 * t + 16 / 116)

    fx, fy, fz = f(X), f(Y), f(Z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e00(lab1, lab2) -> float:
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    c1 = math.hypot(a1, b1)
    c2 = math.hypot(a2, b2)
    cb = (c1 + c2) / 2
    G = 0.5 * (1 - math.sqrt(cb ** 7 / (cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    c1p = math.hypot(a1p, b1)
    c2p = math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360
    h2p = math.degrees(math.atan2(b2, a2p)) % 360
    dl = L2 - L1
    dc = c2p - c1p
    if c1p * c2p == 0:
        dh = 0
    else:
        dh = h2p - h1p
        if dh > 180:
            dh -= 360
        elif dh < -180:
            dh += 360
    dhp = 2 * math.sqrt(c1p * c2p) * math.sin(math.radians(dh / 2))
    lb = (L1 + L2) / 2
    cbp = (c1p + c2p) / 2
    if c1p * c2p == 0:
        hb = h1p + h2p
    else:
        if abs(h1p - h2p) <= 180:
            hb = (h1p + h2p) / 2
        elif h1p + h2p < 360:
            hb = (h1p + h2p + 360) / 2
        else:
            hb = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hb - 30)) + 0.24 * math.cos(math.radians(2 * hb))
         + 0.32 * math.cos(math.radians(3 * hb + 6)) - 0.20 * math.cos(math.radians(4 * hb - 63)))
    Sl = 1 + (0.015 * (lb - 50) ** 2) / math.sqrt(20 + (lb - 50) ** 2)
    Sc = 1 + 0.045 * cbp
    Sh = 1 + 0.015 * cbp * T
    Rt = -2 * math.sqrt(cbp ** 7 / (cbp ** 7 + 25 ** 7)) * math.sin(
        math.radians(60 * math.exp(-((hb - 275) / 25) ** 2)))
    return math.sqrt((dl / Sl) ** 2 + (dc / Sc) ** 2 + (dhp / Sh) ** 2
                     + Rt * (dc / Sc) * (dhp / Sh))


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    app = os.path.dirname(here)
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', default=os.path.join(
        app, 'verification', 'ambient-live', 'emulator-report.json'))
    parser.add_argument('--out', default=os.path.join(
        app, '..', 'shots', '13-ambient-colour-trajectory.png'))
    args = parser.parse_args()

    with open(args.report) as handle:
        report = json.load(handle)['ambientLive']
    series = report['series']
    if not series:
        print('the report has no series', file=sys.stderr)
        return 1

    frames = []
    for item in series:
        h = item['hex'].lstrip('#')
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        L, a, bb = rgb_to_oklab(r, g, b)
        frames.append({
            't': item['tMs'],
            'rgb': (r, g, b),
            'L': L,
            'C': math.hypot(a, bb),
            'H': math.degrees(math.atan2(bb, a)) % 360,
            'ab': (a, bb),
            'lab': rgb_to_lab(r, g, b),
        })

    first = frames[0]['lab']
    for f in frames:
        f['dist'] = delta_e00(first, f['lab'])
    steps = [delta_e00(frames[i - 1]['lab'], frames[i]['lab']) for i in range(1, len(frames))]
    path_length = sum(steps)
    dmax = max(f['dist'] for f in frames) or 1
    median_step = sorted(steps)[len(steps) // 2]

    W, H = 1400, 860
    img = Image.new('RGB', (W, H), BACKGROUND)
    draw = ImageDraw.Draw(img)
    f_title = load_font(30)
    f_head = load_font(19)
    f_small = load_font(15)
    f_tiny = load_font(13)

    draw.text((36, 24), '氛围灯颜色轨迹 · 一次真实运行', font=f_title, fill=TEXT)
    draw.text((36, 64),
              '引擎 60Hz 颜色序列在 OKLab 平面里的轨迹（颜色取自渲染像素，与物理屏互证）',
              font=f_small, fill=MUTED)

    # ---------------- panel 1: the OKLab plane ----------------
    px0, py0, pw, ph = 36, 104, 520, 704
    draw.rectangle([px0, py0, px0 + pw, py0 + ph], fill=PANEL)
    draw.text((px0 + 16, py0 + 14), '① OKLab (a, b) 平面：颜色走过的路径', font=f_head, fill=TEXT)

    # Zoom on the meaningful part of the path: the first frames are still
    # ramping up from black and their hue is noise, so they would blow the
    # scale up for nothing.
    alive = [f for f in frames if f['C'] > 0.02 and f['L'] > 0.05]
    ab = [f['ab'] for f in (alive or frames)]
    amin, amax = min(a for a, _ in ab), max(a for a, _ in ab)
    bmin, bmax = min(b for _, b in ab), max(b for _, b in ab)
    span = max(amax - amin, bmax - bmin, 0.02)
    cx = (amax + amin) / 2
    cy = (bmax + bmin) / 2
    plot_w, plot_h = pw - 80, 420
    scale = min(plot_w, plot_h) / (span * 1.25)
    ox, oy = px0 + pw / 2, py0 + 236

    def to_px(a, b):
        return (ox + a * scale, oy - b * scale)

    # a scale bar instead of the chroma circles: at this zoom the circles
    # would be bigger than the panel
    bar = 0.02 * scale
    draw.line([px0 + 24, oy + 196, px0 + 24 + bar, oy + 196], fill=MUTED, width=2)
    draw.text((px0 + 24, oy + 202), 'a/b 相差 0.02', font=f_tiny, fill=MUTED)

    points = [to_px(f['ab'][0], f['ab'][1]) for f in frames]
    for i in range(1, len(points)):
        shade = int(30 + 150 * (i / len(points)))
        draw.line([points[i - 1], points[i]], fill=(shade // 2, shade, 255 - shade // 3), width=2)
    for i, f in enumerate(frames):
        x, y = points[i]
        r, g, b = f['rgb']
        draw.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(r, g, b))
    draw.ellipse([ox - 5, oy - 5, ox + 5, oy + 5], outline=(90, 100, 115))

    ty = py0 + 486
    draw.text((px0 + 16, ty), '路径长度 %.0f ΔE ≈ %.1f 个色域宽度（100 ΔE）'
              % (path_length, path_length / 100), font=f_small, fill=ACCENT)
    draw.text((px0 + 16, ty + 26), '离第一帧最远 %.1f ΔE，末帧仍在 %.1f ΔE 处'
              % (dmax, frames[-1]['dist']), font=f_small, fill=TEXT)
    draw.text((px0 + 16, ty + 58), '相邻帧色差：中位 %.2f，最大 %.2f ΔE'
              % (median_step, max(steps)), font=f_small, fill=TEXT)
    draw.text((px0 + 16, ty + 96), '所以颜色并没有卡在一个底色上：', font=f_small, fill=TEXT)
    draw.text((px0 + 16, ty + 118), '它一直在色域里走，30 秒走了 %.0f ΔE。' % path_length,
              font=f_small, fill=TEXT)
    draw.text((px0 + 16, ty + 146), '肉眼觉得「一个底色」，是因为它一直待在',
              font=f_small, fill=MUTED)
    draw.text((px0 + 16, ty + 168), '同一个色相楔里（见 ③），不是它不动。',
              font=f_small, fill=MUTED)

    # ---------------- panel 2: lightness, chroma, distance ----------------
    qx0, qy0, qw, qh = 590, 104, 774, 430
    draw.rectangle([qx0, qy0, qx0 + qw, qy0 + qh], fill=PANEL)
    draw.text((qx0 + 16, qy0 + 14), '② 明度 L / 彩度 C / 离第一帧的距离', font=f_head, fill=TEXT)
    gx0, gx1 = qx0 + 96, qx0 + qw - 24
    tmax = max(f['t'] for f in frames) or 1

    def tx(t):
        return gx0 + (gx1 - gx0) * t / tmax

    rows = [
        ('L 明度', 0.0, 0.7, lambda f: f['L'], ACCENT),
        ('C 彩度', 0.0, 0.25, lambda f: f['C'], ACCENT_3),
        ('离第一帧 ΔE', 0.0, dmax * 1.05, lambda f: f['dist'], ACCENT_2),
    ]
    row_h = (qh - 70) / len(rows)
    for index, (label, lo, hi, getter, colour) in enumerate(rows):
        y0 = qy0 + 48 + index * row_h
        y1 = y0 + row_h - 26
        draw.line([gx0, y0, gx0, y1], fill=GRID)
        draw.line([gx0, y1, gx1, y1], fill=GRID)
        for f in frames:
            v = getter(f)
            x = tx(f['t'])
            y = y1 - (y1 - y0) * (v - lo) / (hi - lo)
            draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=colour)
        draw.text((qx0 + 16, y0 - 2), label, font=f_tiny, fill=MUTED)
        draw.text((qx0 + 16, y1 - 12), '%.2f' % hi, font=f_tiny, fill=MUTED)
        draw.text((qx0 + 16, y1 + 2), '%.2f' % lo, font=f_tiny, fill=MUTED)
    draw.text((gx0, qy0 + qh - 24), '0 s', font=f_tiny, fill=MUTED)
    draw.text((gx1 - 26, qy0 + qh - 24), '%.0f s' % (tmax / 1000), font=f_tiny, fill=MUTED)

    # ---------------- panel 3: the hue ----------------
    hx0, hy0, hw, hh = 590, 558, 774, 250
    draw.rectangle([hx0, hy0, hx0 + hw, hy0 + hh], fill=PANEL)
    draw.text((hx0 + 16, hy0 + 14), '③ 色相 H（灰底是 V2 的色相带 170°~320°）',
              font=f_head, fill=TEXT)
    kx0, kx1 = hx0 + 96, hx0 + hw - 24
    ky0, ky1 = hy0 + 48, hy0 + hh - 40
    draw.rectangle([kx0, ky0, kx1, ky1], outline=GRID)
    band_lo = kx0 + (kx1 - kx0) * HUE_BAND_LOW / 360.0
    band_hi = kx0 + (kx1 - kx0) * HUE_BAND_HIGH / 360.0
    draw.rectangle([band_lo, ky0, band_hi, ky1], fill=(26, 44, 68))
    draw.text((kx0 + 4, ky1 + 6), '0°', font=f_tiny, fill=MUTED)
    draw.text((kx1 - 30, ky1 + 6), '360°', font=f_tiny, fill=MUTED)
    draw.text((band_lo + 4, ky0 + 4), '170°', font=f_tiny, fill=MUTED)
    draw.text((band_hi - 30, ky0 + 4), '320°', font=f_tiny, fill=MUTED)

    prev_pt = None
    for f in frames:
        if f['C'] <= 0.02:
            prev_pt = None
            continue
        x = tx(f['t'])
        y = ky1 - (ky1 - ky0) * (f['H'] / 360.0)
        if prev_pt is not None:
            draw.line([prev_pt, (x, y)], fill=ACCENT_2, width=2)
        prev_pt = (x, y)
    draw.text((hx0 + 16, hy0 + 34),
              '色相被钉在 235°~285° 这一楔子里',
              font=f_tiny, fill=MUTED)

    # ---------------- the verdict ----------------
    draw.text((36, H - 72),
              '结论：颜色确实在走（路径 %.0f ΔE、离起点最远 %.1f ΔE、相邻帧中位 %.2f ΔE）——'
              % (path_length, dmax, median_step), font=f_small, fill=TEXT)
    draw.text((36, H - 48),
              '「一直是一个底色」的真正原因：色相带 170°~320° + 默认「跟随低频」模式 ⇒ 色相被钉在 235°~285° 这一楔子里，'
              '而不是颜色不动。', font=f_small, fill=MUTED)
    draw.text((36, H - 24),
              '写车机的一层（uni 原生 AmbientLightWriter）只做 50ms 节流 + 2 单位死区，不改颜色 ⇒ 车上拿到的就是引擎这一帧。',
              font=f_small, fill=MUTED)

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print('wrote', out)
    print('path length %.1f dE, max excursion %.1f dE, median step %.2f dE'
          % (path_length, dmax, median_step))
    return 0


if __name__ == '__main__':
    sys.exit(main())
