#!/usr/bin/env python3
"""Build/install a synthetic navigation source, strictly emulator-only."""
import argparse
from pathlib import Path
import subprocess
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', default='emulator-5580')
args = parser.parse_args()
if not args.serial.startswith('emulator-') or not args.serial[9:].isdigit():
    parser.error('Emulator serial required')
adb = ['adb', '-s', args.serial]
if subprocess.check_output(adb + ['shell', 'getprop', 'ro.kernel.qemu'], text=True).strip() != '1':
    raise SystemExit('Refusing to install on a physical device')
root = Path(__file__).resolve().parents[1]
sdk = Path('/data/tools/linkco-android/sdk')
build = sdk / 'build-tools/36.0.0'
java = Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin')
android = sdk / 'platforms/android-9/android.jar'
source = root / 'app/native-tests/test-navigation'
out = root / 'app/native-tests/build/live-navigation'
classes = out / 'classes'
classes.mkdir(parents=True, exist_ok=True)

def run(*command):
    subprocess.run([str(part) for part in command], check=True)

run(java / 'javac', '-source', '8', '-target', '8', '-Xlint:-options', '-encoding',
    'UTF-8', '-bootclasspath', android, '-d', classes, *source.rglob('*.java'))
run(java / 'java', '-cp', sdk / 'cmdline-tools/latest/lib/r8.jar',
    'com.android.tools.r8.D8', '--min-api', '26', '--lib', android,
    '--output', out, *classes.rglob('*.class'))
run(build / 'aapt2', 'link', '-I', android, '--manifest', source / 'AndroidManifest.xml',
    '-o', out / 'unsigned.apk')
with zipfile.ZipFile(out / 'unsigned.apk', 'a', zipfile.ZIP_DEFLATED) as apk:
    apk.write(out / 'classes.dex', 'classes.dex')
run(java / 'java', '-jar', build / 'lib/apksigner.jar', 'sign', '--ks',
    sdk.parent / 'uni-debug.keystore', '--ks-pass', 'pass:android', '--ks-key-alias',
    'uni-debug', '--v4-signing-enabled', 'false', '--out', out / 'fixture.apk', out / 'unsigned.apk')
run(*adb, 'install', '-r', out / 'fixture.apk')
print('Synthetic live map installed on emulator only; this is not an AMap APK.')
