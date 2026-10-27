#!/usr/bin/env python3
"""Compile official-entry regressions; --emulator runs isolated, synthetic Android 9 tests.
Never installs the Launcher or touches a vehicle. No network dependency.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration'
TEST = ROOT / 'app/native-tests/test-official-entry'
HARNESS = 'xyz.i4o.uni.fixture.officialentry'
PROVIDER = 'ecarx.calendar'


def run(*args):
    subprocess.run([str(v) for v in args], cwd=ROOT, check=True)


def capture(*args):
    return subprocess.check_output([str(v) for v in args], cwd=ROOT, text=True, timeout=45)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sdk', type=Path, default=Path('/data/tools/linkco-android/sdk'))
    p.add_argument('--java-bin', type=Path, default=Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin'))
    p.add_argument('--emulator', help='Explicit emulator-NNNN serial; never accepts a vehicle')
    args = p.parse_args()
    sdk = args.sdk.resolve()
    platform = sdk / 'platforms/android-9/android.jar'
    if not platform.exists():
        platform = sdk / 'platforms/android-28/android.jar'
    mock = platform.parent / 'optional/android.test.mock.jar'
    java, javac = args.java_bin / 'java', args.java_bin / 'javac'
    build_tools = sdk / 'build-tools/36.0.0'
    installed = []
    if args.emulator:
        if not args.emulator.startswith('emulator-') or not args.emulator[9:].isdigit():
            raise SystemExit('Refusing a non-emulator serial')
        adb = ['adb', '-s', args.emulator]
        if capture(*adb, 'shell', 'getprop', 'ro.kernel.qemu').strip() != '1':
            raise SystemExit('Refusing a non-QEMU device')
        for package in [HARNESS, PROVIDER]:
            if 'package:' in capture(*adb, 'shell', 'pm', 'list', 'packages', package):
                raise SystemExit(f'Refusing to replace existing package {package}; remove only your own old fixture manually')
    with tempfile.TemporaryDirectory(prefix='uni-official-entry-') as temp:
        out = Path(temp)
        assets = out / 'assets'
        assets.mkdir()
        shutil.copy2(ROOT / 'analysis/official-widgets.json', assets)
        apks = {}
        for name, sources, manifest, resources, asset_dir in [
            ('harness', [*[SOURCE / (n + '.java') for n in ['OfficialCatalog', 'OfficialEntryAdapter', 'OfficialWidgetActivity', 'AppRepository', 'OfficialCarContract']], *TEST.joinpath('src').rglob('*.java')], TEST / 'AndroidManifest.xml', None, assets),
            ('provider', list(TEST.joinpath('provider').rglob('*.java')), TEST / 'provider/AndroidManifest.xml', TEST / 'provider/res', None),
        ]:
            dest = out / name
            classes = dest / 'classes'
            classes.mkdir(parents=True)
            run(javac, '-source', '8', '-target', '8', '-Xlint:-options', '-encoding', 'UTF-8',
                '-bootclasspath', str(platform) + ':' + str(mock), '-d', classes, *sources)
            run(java, '-cp', sdk / 'cmdline-tools/latest/lib/r8.jar', 'com.android.tools.r8.D8',
                '--min-api', '24', '--lib', platform, '--lib', mock, '--output', dest, *classes.rglob('*.class'))
            link = [build_tools / 'aapt2', 'link', '-I', platform, '--manifest', manifest, '-o', dest / 'unsigned.apk']
            if resources:
                run(build_tools / 'aapt2', 'compile', '--dir', resources, '-o', dest / 'res.zip')
                link += ['-R', dest / 'res.zip']
            if asset_dir:
                link += ['-A', asset_dir]
            run(*link)
            with zipfile.ZipFile(dest / 'unsigned.apk', 'a', zipfile.ZIP_DEFLATED) as apk:
                apk.write(dest / 'classes.dex', 'classes.dex')
            apks[name] = dest / 'test-only.apk'
            run(java, '-jar', build_tools / 'lib/apksigner.jar', 'sign', '--ks', sdk.parent / 'uni-debug.keystore',
                '--ks-pass', 'pass:android', '--ks-key-alias', 'uni-debug', '--v4-signing-enabled', 'false',
                '--out', apks[name], dest / 'unsigned.apk')
        print('PASS: API 28 compilation, D8 and test-only APK packaging', flush=True)
        if not args.emulator:
            print('No device accessed. Pass --emulator emulator-5580 to execute synthetic regressions.')
            return
        try:
            for name, package in [('provider', PROVIDER), ('harness', HARNESS)]:
                run(*adb, 'install', '-t', apks[name])
                installed.append(package)
            for phase in ['granted', 'denied']:
                run(*adb, 'shell', 'appwidget', 'grantbind' if phase == 'granted' else 'revokebind', '--package', HARNESS, '--user', '0')
                result = capture(*adb, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'phase', phase,
                                 HARNESS + '/xyz.i4o.uni.launcher.integration.OfficialEntryInstrumentation')
                print(result, flush=True)
                if 'passed=true' not in result or 'FAIL ' in result:
                    raise SystemExit(f'Instrumentation failed ({phase})')
        finally:
            for package in reversed(installed):
                run(*adb, 'uninstall', package)
        print('PASS: isolated emulator tests; fixtures removed. No real OEM app or vehicle field verified.')


if __name__ == '__main__':
    main()
