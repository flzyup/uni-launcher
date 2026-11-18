#!/usr/bin/env python3
"""Run production theme widgets in a disposable Android UI shell, never a car.

Avoids OEM boot services, ADB restarts, real controls and persisted appearance.
The integration test still imports the launcher's production components/assets.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--serial', default='emulator-5554')
p.add_argument('--quick', action='store_true', help='18 representative theme/screens')
p.add_argument('--flutter', default=shutil.which('flutter') or '/data/tools/flutter/bin/flutter')
p.add_argument('--out', type=Path, default=ROOT / 'app/verification/theme-contrast')
args = p.parse_args()
adb = shutil.which('adb') or '/data/tools/linkco-android/sdk/platform-tools/adb'
if not args.serial.startswith('emulator-') or subprocess.check_output(
    [adb, '-s', args.serial, 'shell', 'getprop', 'ro.kernel.qemu'], timeout=15).strip() != b'1':
    raise SystemExit('Only an Android emulator is permitted')
fixture = ROOT / 'app/build/theme-contrast-fixture'
subprocess.run([args.flutter, 'create', '--no-pub', '--platforms=android',
    '--project-name', 'uni_theme_verification', '--org', 'xyz.i4o.uni', str(fixture)], check=True)
app = ROOT / 'app'
shutil.copytree(app / 'assets', fixture / 'assets', dirs_exist_ok=True)
asset_dirs = sorted(str(d.relative_to(fixture)) + '/' for d in
    (fixture / 'assets').rglob('*') if d.is_dir() and d.name != 'shaders'
    and any(f.is_file() for f in d.iterdir()))
shaders = sorted(str(f.relative_to(fixture)) for f in
    (fixture / 'assets/shaders').glob('*.frag'))
(fixture / 'pubspec.yaml').write_text(f'''name: uni_theme_verification
publish_to: none
version: 1.0.0+1
environment:
  sdk: '>=3.11.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  uni_launcher:
    path: {app}
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
flutter:
  uses-material-design: true
  shaders:
''' + ''.join('    - ' + f + '\n' for f in shaders) + '  assets:\n' +
    ''.join('    - ' + d + '\n' for d in asset_dirs))
for name in ['integration_test/theme_contrast_test.dart', 'test/fake_gateway.dart',
             'test_driver/theme_contrast_driver.dart']:
    target = fixture / name
    target.parent.mkdir(exist_ok=True)
    shutil.copy(app / name, target)
test = fixture / 'integration_test/theme_contrast_test.dart'
s = test.read_text().replace("import 'package:flutter/material.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';")
s = s.replace('    final gateway = FakeGateway();',
    '    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);\n'
    '    final gateway = FakeGateway();')
test.write_text(s)
gradle = fixture / 'android/app/build.gradle.kts'
gradle.write_text(gradle.read_text().replace('targetSdk = flutter.targetSdkVersion', 'targetSdk = 28'))
env = dict(os.environ, UNI_EMULATOR_SERIAL=args.serial,
    UNI_THEME_VERIFY_OUT=str(args.out.resolve()))
for key in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']:
    env.pop(key, None)
subprocess.run([args.flutter, 'pub', 'get', '--offline'], cwd=fixture, env=env, check=True)
subprocess.run([args.flutter, 'drive', '--no-pub', '--profile', '-d', args.serial,
    '--driver=test_driver/theme_contrast_driver.dart',
    '--target=integration_test/theme_contrast_test.dart'] +
    (['--dart-define=UNI_THEME_VERIFY_QUICK=true'] if args.quick else []),
    cwd=fixture, env=env, check=True)
report = json.loads((args.out / 'report.json').read_text())
for name in report['files']:
    if not (args.out / name).is_file():
        raise SystemExit('Missing screenshot: ' + name)
print('Report and screenshots:', args.out.resolve())
