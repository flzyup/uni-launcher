#!/usr/bin/env python3
"""Exercise both navigation switches on an isolated Android 9 emulator.

Uses real settings controls, checks window policy and dock geometry, and restores
its original settings. It refuses physical devices and never targets a car.
"""
import argparse
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('--serial', default='emulator-5580')
a = p.parse_args()
if not re.fullmatch(r'emulator-\d+', a.serial):
    raise SystemExit('Refusing non-emulator target')
adb = ['adb', '-s', a.serial]
package = 'xyz.i4o.uni.launcher'

def run(*args):
    return subprocess.check_output([*adb, *args], timeout=25).decode()

def shell(*args):
    return run('shell', *args).strip()

if shell('getprop', 'ro.kernel.qemu') != '1' or shell('getprop', 'ro.build.version.sdk') != '28':
    raise SystemExit('Android 9 emulator required')

def state():
    result = shell('dumpsys', 'activity', package + '/.MainActivity', '--uni-state')
    return next((json.loads(line.split('UNI_STATE=', 1)[1]) for line in result.splitlines() if 'UNI_STATE=' in line), None)

def nodes():
    for _ in range(5):
        shell('rm', '-f', '/sdcard/uni-nav-switches.xml')
        result = shell('uiautomator', 'dump', '/sdcard/uni-nav-switches.xml')
        if 'dumped to:' in result:
            return list(ET.fromstring(run('shell', 'cat', '/sdcard/uni-nav-switches.xml')).iter('node'))
        time.sleep(.3)
    raise AssertionError('Could not obtain a fresh accessibility hierarchy')

def bounds(node):
    return list(map(int, re.findall(r'\d+', node.get('bounds', ''))))

def tap(node):
    l,t,r,b = bounds(node)
    shell('input','tap',str((l+r)//2),str((t+b)//2))
    time.sleep(.4)

def settings():
    shell('am','start','-n',package+'/.MainActivity','--ez','uniSettings','true')
    time.sleep(.7)
    for node in nodes():
        if node.get('content-desc') == '系统设置':
            tap(node)
            break

def set_switch(title, wanted):
    for attempt in range(8):
        for node in nodes():
            if node.get('class') != 'android.widget.Switch' or node.get('content-desc') != title:
                continue
            l,t,r,b = bounds(node)
            if b-t < 30:
                break
            if (node.get('checked') == 'true') != wanted:
                tap(node)
            return
        shell('input','swipe','1200','840','1200','430','300')
        time.sleep(.3)
    raise AssertionError('Switch not visible: ' + title)

def nav_state():
    policy = shell('dumpsys','window','policy')
    m = re.search(r'BarController.NavigationBar\s+\n?\s*mState=WINDOW_STATE_(\w+)', policy)
    if not m:
        raise AssertionError('Navigation state missing')
    return m.group(1)

def wait_for(label, predicate):
    for _ in range(70):
        current = state()
        if current and predicate(current):
            return current
        time.sleep(.1)
    raise AssertionError(label + ': ' + str(state()))

def verify(global_on, hidden):
    s = wait_for('switch states', lambda x: x.get('systemNavigationHidden') == hidden
                 and x.get('globalDock', {}).get('enabled') == global_on
                 and x.get('globalDock', {}).get('running') == global_on
                 and (not global_on or (x.get('globalDock',{}).get('visible')
                      and x.get('globalDock',{}).get('rendering')
                      and abs(x.get('viewportHeightPx',0)-x.get('globalDock',{}).get('y',-1000)) <= 2)))
    expected_viewport = {True: {False: 888, True: 984}, False: {False: 984, True: 1080}}[global_on][hidden]
    for _ in range(70):
        if s.get('viewportHeightPx') == expected_viewport:
            break
        time.sleep(.1)
        s = state()
    if s.get('viewportHeightPx') != expected_viewport:
        raise AssertionError(f'viewport did not settle: expected {expected_viewport}, got {s.get("viewportHeightPx")}')
    for _ in range(40):
        nav = nav_state()
        if nav == ('HIDDEN' if hidden else 'SHOWING'):
            break
        time.sleep(.1)
    if nav != ('HIDDEN' if hidden else 'SHOWING'):
        raise AssertionError(f'navigation: {nav}, expected hidden={hidden}')
    dock = s['globalDock']
    if global_on:
        if not dock.get('visible') or not dock.get('rendering'):
            raise AssertionError('global dock not visible/rendering')
        if hidden and dock['y'] + dock['height'] != 1080:
            raise AssertionError('dock not at bottom: ' + str(dock))
        if not hidden and dock['y'] + dock['height'] >= 1080:
            raise AssertionError('dock overlaps system nav: ' + str(dock))
        # The content must end at the dock edge, without a second inset.
        if abs(s['viewportHeightPx'] - dock['y']) > 2:
            raise AssertionError('content/dock gap: ' + str((s['viewportHeightPx'], dock['y'])))
    else:
        # With the overlay off, LauncherShell always builds the inline dock.
        # Accessibility reports transformed FittedBox children at zero size on
        # API 28, so assert the usable height and retain a visual artifact.
        if s['viewportHeightPx'] != expected_viewport:
            raise AssertionError('inline desktop did not use correct height: ' + str(s))
        run('exec-out','screencap','-p','/sdcard/uni-inline-dock.png')
    policy = shell('settings','get','global','policy_control')
    if hidden != ('immersive.full=*,-com.ecarx.parking,-com.android.packageinstaller' in policy):
        raise AssertionError('unexpected policy: ' + policy)
    print(f'PASS global={global_on} system_hidden={hidden} nav={nav} viewport={s["viewportHeightPx"]} dock_y={dock.get("y")}', flush=True)

settings()
initial = state()
if not initial or not initial.get('systemNavigationGranted'):
    raise SystemExit('Launcher missing or WRITE_SECURE_SETTINGS not granted')
initial_global = initial['globalDock']['enabled']
initial_hidden = initial['systemNavigationHidden']
try:
    for global_on, hidden in [(True,False),(True,True),(False,True),(False,False),(True,False),(True,True)]:
        settings()
        set_switch('全局底栏',global_on)
        # Detect unintended coupling immediately; switching global dock must
        # never change the previously selected system navigation state.
        s = wait_for('global toggle', lambda x: x.get('globalDock',{}).get('enabled') == global_on)
        before_hidden = s['systemNavigationHidden']
        if before_hidden != initial_hidden:
            raise AssertionError(f'global switch changed system state: {initial_hidden} -> {before_hidden}')
        settings()
        set_switch('隐藏系统原有导航栏',hidden)
        verify(global_on,hidden)
        initial_hidden = hidden
    # Exercise the platform-signed resource-overlay path used by the vehicle.
    # Starting while hidden installs/enables the native insets adapter.
    shell('am','force-stop',package)
    settings()
    s = wait_for('native overlay startup', lambda x: x.get('globalDock',{}).get('nativeNavigationInsets') is True)
    verify(True,True)
    set_switch('隐藏系统原有导航栏',False)
    verify(True,False)
    settings()
    set_switch('隐藏系统原有导航栏',True)
    verify(True,True)
    print('PASS platform-signed native insets startup and both toggle directions',flush=True)
    # An edge swipe must reveal the stock bar transiently without changing
    # the persisted switch or disabling the UNI dock.
    shell('input','swipe','960','1079','960','790','250')
    policy = shell('dumpsys','window','policy')
    match = re.search(r'BarController.NavigationBar\s+\n?\s*mState=WINDOW_STATE_(\w+)\s+\n?\s*mTransientBar=(\w+)', policy)
    if not match or match.group(1) not in ('SHOWING','SHOWING_TRANSIENT'):
        raise AssertionError('edge swipe did not reveal navigation: ' + (match.group(0) if match else 'missing'))
    current = state()
    if not current['systemNavigationHidden'] or not current['globalDock']['visible']:
        raise AssertionError('edge swipe changed persisted settings')
    print('PASS bottom swipe temporarily reveals system navigation',flush=True)
    def verify_external(expected_bottom):
        shell('am','start','-a','android.settings.SETTINGS')
        for _ in range(70):
            stacks = shell('am','stack','list')
            matching = [part for part in stacks.split('\n\n') if 'com.android.settings/' in part and 'visible=true' in part]
            if matching:
                m = re.search(r'Stack id=\d+ bounds=\[0,0\]\[1920,(\d+)\]', matching[0])
                if m and int(m.group(1)) == expected_bottom:
                    break
            time.sleep(.1)
        else:
            raise AssertionError('external app does not reserve the dock area: '+stacks)
        dock_output = shell('dumpsys','activity','service',package+'/.GlobalDockService')
        if 'UNI_GLOBAL_DOCK=' not in dock_output or not json.loads(dock_output.split('UNI_GLOBAL_DOCK=',1)[1].splitlines()[0]).get('visible'):
            raise AssertionError('dock missing in external app')
        print(f'PASS external app content ends at y={expected_bottom}',flush=True)
    verify_external(984)
    settings()
    set_switch('隐藏系统原有导航栏',False)
    verify(True,False)
    verify_external(888)
finally:
    settings()
    set_switch('全局底栏',initial_global)
    settings()
    set_switch('隐藏系统原有导航栏',initial['systemNavigationHidden'])
    print('Original settings restored',flush=True)
