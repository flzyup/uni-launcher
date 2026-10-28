#!/usr/bin/env python3
"""Export the approved connected UNI mark to Android, SVG and high-res PNG.

Run from any directory with Python 3 and Pycairo installed. Paths, gradients
and proportions are shared by all exports; no generated bitmap is upscaled.
"""
import re
from pathlib import Path
import xml.etree.ElementTree as ET

import cairo

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / 'app/android/app/src/main/res'
OUT = ROOT / 'design/publishing'
ANDROID = 'http://schemas.android.com/apk/res/android'
AAPT = 'http://schemas.android.com/aapt'
ET.register_namespace('android', ANDROID)
ET.register_namespace('aapt', AAPT)

# Optical redraw of concept 01, on a 512-unit square. U and N share one
# continuous outline; I remains separated by a 20-unit negative-space gap.
MARK = (
    'M 46 177 L 88 177 L 88 263 '
    'C 88 286 100 298 123 298 L 146 298 '
    'C 168 298 180 286 180 263 L 180 217 '
    'C 180 192 196 176 218 176 '
    'C 231 176 240 181 250 190 L 359 294 L 359 177 '
    'L 401 177 L 401 302 '
    'C 401 326 386 341 364 341 '
    'C 351 341 341 336 332 327 L 233 234 '
    'C 227 228 222 229 222 237 L 222 263 '
    'C 222 313 194 341 146 341 L 123 341 '
    'C 73 341 46 313 46 263 Z'
)
I_MARK = ('M 424 177 L 460 177 C 462 177 464 179 464 181 '
          'L 464 337 C 464 339 462 341 460 341 L 424 341 '
          'C 422 341 420 339 420 337 L 420 181 '
          'C 420 179 422 177 424 177 Z')
TILE = 'M 0 0 L 512 0 L 512 512 L 0 512 Z'
BACKGROUND = '#0D203B'
GRADIENTS = {
    'mark': (150, 177, 360, 341, [(0, '#F7FAFF'), (.50, '#DEEEFC'), (1, '#83B6FF')]),
    'i': (420, 177, 464, 341, [(0, '#A1E4F5'), (1, '#61AEF5')]),
}
LAYERS = [(TILE, BACKGROUND), (MARK, 'mark'), (I_MARK, 'i')]


def android_attrs(**attrs):
    return {f'{{{ANDROID}}}{k}': str(v) for k, v in attrs.items()}


def write_android(name, monochrome=False):
    vector = ET.Element('vector', android_attrs(
        width='96dp', height='96dp', viewportWidth=512, viewportHeight=512))
    for path, paint in (LAYERS[1:] if monochrome else LAYERS):
        node = ET.SubElement(vector, 'path', android_attrs(pathData=path))
        if monochrome:
            node.set(f'{{{ANDROID}}}fillColor', '#FFFFFF')
            continue
        if paint.startswith('#'):
            node.set(f'{{{ANDROID}}}fillColor', paint)
            continue
        attr = ET.SubElement(node, f'{{{AAPT}}}attr', {'name': 'android:fillColor'})
        x1, y1, x2, y2, stops = GRADIENTS[paint]
        gradient = ET.SubElement(attr, 'gradient', android_attrs(
            type='linear', startX=x1, startY=y1, endX=x2, endY=y2))
        for offset, color in stops:
            ET.SubElement(gradient, 'item', android_attrs(offset=offset, color=color))
    ET.indent(vector, space='  ')
    ET.ElementTree(vector).write(RES / 'drawable' / name, encoding='utf-8', xml_declaration=True)


def write_svg():
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">',
             '<title>UNI桌面 · 连笔 UNI</title>', '<defs>']
    for name, (x1, y1, x2, y2, stops) in GRADIENTS.items():
        parts.append(f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" '
                     f'x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">')
        parts.extend(f'<stop offset="{offset}" stop-color="{color}"/>' for offset, color in stops)
        parts.append('</linearGradient>')
    parts.append('</defs>')
    for path, paint in LAYERS:
        fill = paint if paint.startswith('#') else f'url(#{paint})'
        parts.append(f'<path d="{path}" fill="{fill}"/>')
    parts.append('</svg>')
    (OUT / 'uni-app-icon-connected.svg').write_text('\n'.join(parts) + '\n')


def draw_path(context, data):
    tokens = iter(re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?', data))
    for token in tokens:
        if token == 'Z':
            context.close_path()
        elif token in ('M', 'L', 'C'):
            coords = [float(next(tokens)) for _ in range(6 if token == 'C' else 2)]
            {'M': context.move_to, 'L': context.line_to, 'C': context.curve_to}[token](*coords)
        else:
            raise ValueError(f'Unsupported path token: {token}')


def write_png(path, size):
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    context = cairo.Context(surface)
    context.scale(size / 512, size / 512)
    for data, paint in LAYERS:
        draw_path(context, data)
        if paint.startswith('#'):
            context.set_source_rgb(*[int(paint[i:i+2], 16) / 255 for i in (1, 3, 5)])
            context.fill()
            continue
        x1, y1, x2, y2, stops = GRADIENTS[paint]
        gradient = cairo.LinearGradient(x1, y1, x2, y2)
        for offset, color in stops:
            rgb = [int(color[i:i+2], 16) / 255 for i in (1, 3, 5)]
            gradient.add_color_stop_rgb(offset, *rgb)
        context.set_source(gradient)
        context.fill()
    surface.write_to_png(str(path))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write_android('uni_icon.xml')
    write_android('uni_notification.xml', monochrome=True)
    write_svg()
    for size in (512, 1024, 2048):
        write_png(OUT / f'uni-app-icon-connected-{size}.png', size)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                          ('xxhdpi', 144), ('xxxhdpi', 192)]:
        write_png(RES / f'mipmap-{density}/ic_launcher.png', size)
    print('Exported connected UNI: Android vector, notification glyph, SVG, PNG (up to 2048).')


if __name__ == '__main__':
    main()
