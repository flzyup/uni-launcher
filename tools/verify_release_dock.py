#!/usr/bin/env python3
"""API28 emulator release/AOT smoke via actual settings controls, no run-as.
Requires a normal release build installed with emulator overlay/secure-settings
permissions. Restores both settings and checks the original system policy.
"""
import json, re, subprocess, time, xml.etree.ElementTree as ET
from pathlib import Path

ADB = ['adb', '-s', 'emulator-5580']
PKG = 'xyz.i4o.uni.launcher'
OUT = Path('app/verification/global-dock')
checks = []

def run(*args):
    return subprocess.check_output([*ADB, *args], timeout=30)

def sh(*args):
    return run('shell', *args).decode().strip()

def state(home=False):
    command = ['dumpsys', 'activity', PKG + '/.MainActivity', '--uni-state'] if home else ['dumpsys', 'activity', 'service', PKG + '/.GlobalDockService']
    tag = 'UNI_STATE=' if home else 'UNI_GLOBAL_DOCK='
    return next((json.loads(line.split(tag, 1)[1]) for line in sh(*command).splitlines() if tag in line), {})

def wait(predicate):
    for _ in range(60):
        current = state()
        if predicate(current):
            return current
        time.sleep(.1)
    raise AssertionError('Dock state timeout: ' + str(state()))

def check(name, value):
    checks.append({'name': name, 'passed': bool(value)})
    if not value:
        raise AssertionError(name)

def nodes():
    path = '/sdcard/uni-release-test.xml'
    for _ in range(5):
        sh('rm', '-f', path)
        result = sh('uiautomator', 'dump', path)
        if 'dumped to:' in result:
            return ET.fromstring(run('shell', 'cat', path)).iter('node')
        time.sleep(.3)
    raise AssertionError('No current UI hierarchy; refusing stale coordinates')

def tap_node(node):
    left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
    sh('input', 'tap', str((left + right) // 2), str((top + bottom) // 2))
    time.sleep(.25)

def options():
    sh('am', 'start', '-W', '-n', PKG + '/.MainActivity')
    time.sleep(.4)
    height = state(True)['viewportHeightPx']
    dock = state()
    y = dock['y'] + 48 if dock.get('running') else height - 48
    sh('input', 'swipe', '138', str(y), '138', str(y), '900')
    time.sleep(1.8 if dock.get('nativeNavigationInsets') else .3)
    for _ in range(3):
        tab = next((n for n in nodes() if n.get('content-desc') == '功能接入' and n.get('clickable') == 'true'),None)
        if tab is not None:
            tap_node(tab)
            return
        sh('input', 'swipe', '138', str(y), '138', str(y), '900')
        time.sleep(1)
    raise AssertionError('Settings did not open from Home hold')

def switch(title, value=None):
    for _ in range(6):
        candidates = [n for n in nodes() if n.get('class') == 'android.widget.Switch' and n.get('content-desc', '').startswith(title)]
        for node in candidates:
            left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
            if bottom - top < 40:
                continue
            checked = node.get('checked') == 'true'
            if value is not None and checked != value:
                tap_node(node)
            return checked
        sh('input', 'swipe', '1100', '840', '1100', '450', '350')
    raise AssertionError('Settings switch not visible: ' + title)

def shot(name):
    (OUT / name).write_bytes(run('exec-out', 'screencap', '-p'))

if sh('getprop', 'ro.kernel.qemu') != '1' or sh('getprop', 'ro.product.cpu.abi') != 'x86_64':
    raise SystemExit('Isolated x86_64 emulator required')
OUT.mkdir(parents=True, exist_ok=True)
options()
check('release 0.5.1 home and settings', state(True).get('version') == '0.5.1-flutter')
original_demo = switch('演示数据', True)
original_global = switch('全局底栏')
original_hidden = switch('隐藏系统原有导航栏')
policy = sh('settings', 'get', 'global', 'policy_control')
try:
    switch('全局底栏', True)
    wait(lambda s: s.get('running'))
    # First activation of framework resources may recreate the host Activity.
    options()
    switch('隐藏系统原有导航栏', True)
    native=state().get('nativeNavigationInsets')
    expected='immersive.full=*,-com.ecarx.parking'
    check('system navigation rule excludes OEM camera', expected in sh('settings', 'get', 'global', 'policy_control'))
    shot('release-global-settings.png')
    sh('am', 'start', '-a', 'android.settings.SETTINGS')
    dock = wait(lambda s: s.get('visible') and s.get('rendering'))
    check('AOT globalDockMain renders over external app', True)
    check('full-width bottom edge without gap', dock['x'] == 0 and dock['width'] == 1920 and dock['height'] == 96 and dock['y'] + dock['height'] == 1080)
    shot('release-global-dock.png')
    before = dock['media']['playing']
    sh('input', 'tap', '1063', str(dock['y'] + 48))
    wait(lambda s: s.get('media', {}).get('playing') != before)
    check('release overlay controls shared media', True)
    sh('input', 'tap', '1250', str(dock['y'] + 48))
    panel = wait(lambda s: s.get('panelReady') and s.get('panel') == 'media')
    time.sleep(.8)
    check('AOT globalPanelMain renders music in its own window', panel.get('panelRendering') and panel.get('panelHeight') == 984)
    check('music panel never changes dock geometry', panel['height'] == 96 and panel['screenY'] == 984 and panel['dockRelayouts'] == 0)
    shot('release-global-music.png')
    from PIL import Image, ImageChops, ImageStat
    before_image = Image.open(OUT / 'release-global-dock.png').convert('RGB')
    panel_image = Image.open(OUT / 'release-global-music.png').convert('RGB')
    visible_change = sum(ImageStat.Stat(ImageChops.difference(before_image, panel_image).crop((440,160,1480,824))).mean)
    check('music panel pixels are visible above dock', visible_change > 15)
    sh('input', 'tap', '651', str(dock['y'] + 48))
    panel = wait(lambda s: s.get('panelReady') and s.get('panel') == 'climate')
    check('dock switches panel without hiding or relayout', panel.get('visible') and panel['dockRelayouts'] == 0)
    sh('input', 'keyevent', '4')
    wait(lambda s: not s.get('expanded'))
    check('Back closes independent panel while dock stays visible', state().get('visible'))
    sh('input', 'swipe', '138', str(dock['y'] + 48), '138', str(dock['y'] + 48), '900')
    wait(lambda s: s.get('runtimeOwnerCount') == 2 and not s.get('expanded'))
    check('global Home hold opens settings', state(True).get('flutterViewport', {}).get('settings') is True)
finally:
    options()
    switch('隐藏系统原有导航栏', original_hidden)
    switch('全局底栏', original_global)
    options()
    switch('演示数据', original_demo)
    check('original system policy restored', sh('settings', 'get', 'global', 'policy_control') == policy)
height = state(True)['viewportHeightPx']
sh('input', 'tap', '138', str(height - 48))
time.sleep(.3)
shot('release-home.png')
check('home has no duplicate global dock', bool(state().get('running')) == original_global)
logs = sh('logcat', '-d', '--pid=' + sh('pidof', PKG))
check('no fatal or Dart entrypoint error', not re.search(r'FATAL EXCEPTION|Unhandled Exception|Could not resolve main entrypoint|A RenderFlex overflowed', logs))
(OUT / 'release-report.json').write_text(json.dumps({'version': '0.5.1', 'abi': 'x86_64', 'api': 28, 'passed': len(checks), 'checks': checks, 'systemPolicyRestored': True, 'settingsRestored': True, 'scope': 'Release AOT; isolated emulator only; no real vehicle'}, ensure_ascii=False, indent=2) + '\n')
print('PASS', len(checks), 'release AOT/global dock checks; settings restored')
