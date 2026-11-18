#!/usr/bin/env python3
"""Run raw-window parsing regressions; optionally build an API28 test app.

python3 tools/test_immersive_dock.py --fixture
The fixture exposes normal, sticky, non-sticky and status-only window requests.
It does not mock launcher state or depend on any media app's package name.
"""
import argparse
import json
import time
import subprocess
import tempfile
import zipfile
from pathlib import Path
from test_official_car import executable, android_jar

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fixture', action='store_true')
parser.add_argument('--verify', action='store_true', help='Exercise the installed fixture on an emulator')
parser.add_argument('--device', default='emulator-5554')
parser.add_argument('--sdk', type=Path, default=Path('/data/tools/linkco-android/sdk'))
args = parser.parse_args()
javac = executable(None, 'javac')
java = javac.parent / 'java'
def run(*cmd):
    subprocess.run([str(x) for x in cmd], check=True)
with tempfile.TemporaryDirectory(prefix='uni-immersive-') as out:
    run(javac, '--release', '8', '-d', out,
        ROOT/'app/android/app/src/main/java/xyz/i4o/uni/launcher/overlay/ImmersiveWindowState.java',
        ROOT/'app/native-tests/test/xyz/i4o/uni/launcher/overlay/ImmersiveWindowStateTest.java')
    run(java, '-cp', out, 'xyz.i4o.uni.launcher.overlay.ImmersiveWindowStateTest')
if args.fixture:
    fixture = ROOT/'app/native-tests/test-fixture/immersive'
    out = ROOT/'app/build/immersive-fixture'
    out.mkdir(parents=True, exist_ok=True)
    platform = android_jar(None)
    bt = args.sdk/'build-tools/36.0.0'
    classes = out/'classes'; classes.mkdir(exist_ok=True)
    dex = out/'dex'; dex.mkdir(exist_ok=True)
    raw = out/'raw.apk'
    run(bt/'aapt2', 'link', '-I', platform, '--manifest', fixture/'AndroidManifest.xml', '-o', raw)
    run(javac, '--release', '8', '-cp', platform, '-d', classes,
        *fixture.rglob('*.java'))
    run(java, '-cp', bt/'lib/d8.jar', 'com.android.tools.r8.D8', '--min-api', '24',
        '--lib', platform, '--output', dex, *classes.rglob('*.class'))
    with zipfile.ZipFile(raw, 'a') as apk:
        apk.write(dex/'classes.dex', 'classes.dex')
    apk = out/'UNI-immersive-fixture.apk'
    run(bt/'zipalign', '-f', '4', raw, apk)
    # Android's local development certificate; fixture needs no privileged permission.
    run(java, '-jar', bt/'lib/apksigner.jar', 'sign', '--key',
        '/data/tools/linkco-android/ip753-signing/platform.pk8', '--cert',
        '/data/tools/linkco-android/ip753-signing/platform.x509.pem', apk)
    print(apk)

if args.verify:
    if not args.device.startswith('emulator-'):
        raise SystemExit('UI regression is restricted to emulator devices.')
    def adb(*command):
        return subprocess.check_output(['adb', '-s', args.device, *command], text=True)
    def snapshot():
        text = adb('shell', 'dumpsys', 'activity', 'service', 'xyz.i4o.uni.launcher/.GlobalDockService')
        return json.loads(text.split('UNI_GLOBAL_DOCK=', 1)[1].splitlines()[0])
    def wait_for(predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            value = snapshot()
            if predicate(value): return value
            time.sleep(.15)
        raise AssertionError(value)
    def tap(y): adb('shell', 'input', 'tap', '960', str(y))
    adb('shell', 'am', 'start', '-n', 'xyz.i4o.uni.immersivefixture/.ImmersiveActivity')
    tap(116)
    wait_for(lambda s: s['visible'] and not s['immersive'])
    tap(188)
    wait_for(lambda s: s['immersive'] and not s['visible'] and not s['workspaceReserved'])
    adb('shell', 'input', 'swipe', '960', '1078', '960', '850', '350')
    wait_for(lambda s: s['immersive'] and s['visible'] and s['transientVisible'])
    adb('shell', 'input', 'tap', '587', '1026')
    wait_for(lambda s: s['panel'] == 'climate' and s['visible'])
    time.sleep(2.8)
    assert snapshot()['visible'], 'Panel use must hold transient bar open'
    adb('shell', 'input', 'keyevent', '4')
    wait_for(lambda s: s['immersive'] and not s['visible'] and not s['expanded'])
    tap(332)
    wait_for(lambda s: not s['immersive'] and s['visible'] and s['workspaceReserved'])
    tap(260)
    wait_for(lambda s: s['immersive'] and not s['visible'])
    tap(116)
    wait_for(lambda s: not s['immersive'] and s['visible'])
    tap(404)
    wait_for(lambda s: s['immersive'] and not s['visible'])
    tap(476)
    wait_for(lambda s: s['immersive'] and not s['visible'])
    tap(548)
    wait_for(lambda s: not s['immersive'] and s['visible'] and s['workspaceReserved'])
    adb('shell', 'am', 'start', '-n', 'xyz.i4o.uni.launcher/.MainActivity')
    value = wait_for(lambda s: not s['immersive'] and s['visible'])
    assert value['screenY'] == 984 and value['viewHeight'] == 96, value
    print('Emulator passed: normal, sticky, swipe, panel hold, auto-hide, status-only, non-sticky, legacy, sticky-without-hide-nav, layout-only, return home')
