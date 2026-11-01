#!/usr/bin/env python3
"""Exercise the real Android 9 live texture + synthetic map on an emulator only."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', default='emulator-5580')
parser.add_argument('--out', type=Path, default=Path('app/verification/live-navigation'))
args = parser.parse_args()
adb = ['adb', '-s', args.serial]

def run(*command):
    return subprocess.check_output(adb + list(command), timeout=25)

def shell(*command):
    return run('shell', *command).decode(errors='replace')

if not args.serial.startswith('emulator-') or shell('getprop', 'ro.kernel.qemu').strip() != '1':
    raise SystemExit('Emulator required; this test injects touch and changes emulator UI')
if shell('wm', 'size').strip() != 'Physical size: 1920x1080':
    raise SystemExit('1920x1080 emulator required for baseline touch coordinates')
args.out.mkdir(parents=True, exist_ok=True)

def payload(text, prefix):
    return json.loads(next(line.split(prefix, 1)[1] for line in text.splitlines() if prefix in line))

def state():
    return payload(shell('dumpsys', 'activity', 'xyz.i4o.uni.launcher/.MainActivity', '--uni-state'), 'UNI_STATE=')

def fixture():
    return payload(shell('dumpsys', 'activity', 'com.autonavi.amapauto/xyz.i4o.uni.fixture.navigation.LiveMapActivity'), 'NAV_FIXTURE=')

def wait(predicate):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        value = state()
        if predicate(value):
            return value
        time.sleep(.25)
    raise AssertionError('Live map did not settle')

def screenshot(name):
    (args.out / f'{name}.png').write_bytes(run('exec-out', 'screencap', '-p'))

def tap(x, y):
    shell('input', 'tap', str(x), str(y))

def same_display(current, initial):
    view = current['mapViews'][0]
    for field in ['id', 'textureId', 'displayId', 'width', 'height']:
        assert view[field] == initial[field], (field, view, initial)
    assert view['resizeCount'] == 0, view
    assert view['launchCount'] == initial['launchCount'], 'Page/modal resume restarted the map'
    return view

shell('am', 'force-stop', 'xyz.i4o.uni.launcher')
shell('am', 'start', '-W', '-n', 'xyz.i4o.uni.launcher/.MainActivity')
initial_state = wait(lambda d: d.get('mapViews') and d['mapViews'][0]['ready'])
initial = initial_state['mapViews'][0]
assert initial['renderMode'] == 'realtime' and initial['consumedFrames'] > 0
assert initial_state['navigation']['label'] == 'UNI 实时地图测试源', 'Synthetic fixture required'
screenshot('initial')
time.sleep(1)
advanced = same_display(state(), initial)
assert advanced['consumedFrames'] > initial['consumedFrames'], 'Live frames did not advance'
touch_before = fixture()['touchEvents']
tap(500, 400)
shell('input', 'swipe', '400', '500', '700', '500', '400')
after_pan = fixture()
assert after_pan['touchEvents'] > touch_before
assert state()['flutterViewport']['page'] == 0, 'Map pan also swiped the desktop'
path = shell('pm', 'path', 'com.autonavi.amapauto').strip().splitlines()[0].removeprefix('package:')
assert re.fullmatch(r'[A-Za-z0-9/._=+\-]+', path)
shell('env', 'CLASSPATH=' + path, 'app_process', '/', 'xyz.i4o.uni.fixture.navigation.TouchProbe')
after_pinch = fixture()
assert after_pinch['maxPointers'] == 2 and after_pinch['lastAction'] == 1, after_pinch

cycles = []
for cycle in range(4):
    tap(978, 32)
    hidden = wait(lambda d: d['flutterViewport']['page'] == 1)
    same_display(hidden, initial)
    tap(940, 32)
    shown = wait(lambda d: d['flutterViewport']['page'] == 0 and d['mapViews'][0]['cardVisible'])
    same_display(shown, initial)
    time.sleep(.5)
    current = same_display(state(), initial)
    assert current['consumedFrames'] > advanced['consumedFrames']
    advanced = current
    cycles.append(current)
screenshot('page-return')

shell('am', 'start', '-W', '-n', 'xyz.i4o.uni.launcher/.MainActivity', '--ez', 'uniSettings', 'true')
settings = wait(lambda d: d['flutterViewport']['settings'] and not d['mapViews'][0]['cardVisible'])
same_display(settings, initial)
time.sleep(.5)
screenshot('settings')
tap(138, 936)
wait(lambda d: not d['flutterViewport']['settings'])
tap(1320, 936)
time.sleep(.5)
# Keep rendering the card behind the glass modal. Its barrier must isolate
# input without destroying/recreating the live texture.
screenshot('media-dialog')
touches = fixture()['touchEvents']
tap(740, 350)
assert fixture()['touchEvents'] == touches, 'Dialog touch leaked to map'
shell('input', 'keyevent', '4')
time.sleep(.5)

tap(1217, 114)
time.sleep(.5)
assert fixture()['displayId'] == 0, 'Fullscreen map did not enter physical display'
fullscreen_stack = shell('am', 'stack', 'list')
assert 'com.autonavi.amapauto/' in fullscreen_stack and 'bounds=[0,0][1920,888]' in fullscreen_stack, fullscreen_stack
shell('am', 'start', '-W', '-n', 'xyz.i4o.uni.launcher/.MainActivity')
restored = wait(lambda d: d['mapViews'][0]['cardVisible'] and d['mapViews'][0]['hostVisible'])
time.sleep(.5)
same_display(restored, initial)
assert fixture()['displayId'] == initial['displayId']
returned_stack = shell('am', 'stack', 'list')
card_bounds = f'bounds=[0,0][{initial['width']}x{initial['height']}]'.replace('x', ',')
assert card_bounds in returned_stack, returned_stack
screenshot('fullscreen-return')
live_displays = shell('dumpsys', 'display').count('DisplayDeviceInfo{"UNI Live Navigation ')
assert live_displays == 1, live_displays
shell('am', 'force-stop', 'xyz.i4o.uni.launcher')
deadline = time.monotonic() + 5
while True:
    remaining = shell('dumpsys', 'display').count('DisplayDeviceInfo{"UNI Live Navigation ')
    if remaining == 0 or time.monotonic() >= deadline:
        break
    time.sleep(.1)
assert remaining == 0, remaining
report = {
    'renderMode': 'realtime', 'initial': initial, 'framesAfterWait': advanced['consumedFrames'],
    'touchEventsAfterPan': after_pan['touchEvents'], 'maxPointers': after_pinch['maxPointers'],
    'pageCycles': len(cycles), 'sameTextureAndDisplay': True, 'resizeCount': 0,
    'settingsAndModalInputIsolated': True, 'fullscreenRestored': True,
    'activeDisplays': live_displays, 'displaysAfterProcessStop': remaining,
    'fixture': 'Synthetic Android View; not an AMap/OEM compatibility verdict',
}
(args.out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
