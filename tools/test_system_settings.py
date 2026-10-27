#!/usr/bin/env python3
"""Compile the settings discovery probe; optional --serial runs read-only checks.

No APK install, activity launch or valid audio-mode write. Executes app_process
as the ADB shell, whose permissions differ from the Launcher application's UID.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    sdk = Path('/data/tools/linkco-android/sdk')
    java = Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin')
    platform = sdk / 'platforms/android-28/android.jar'
    if not platform.exists():
        platform = sdk / 'platforms/android-9/android.jar'
    source = ROOT / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration'
    with tempfile.TemporaryDirectory(prefix='uni-settings-') as temp:
        temp = Path(temp)
        classes = temp / 'classes'
        dex = temp / 'dex'
        classes.mkdir()
        dex.mkdir()
        subprocess.run([str(java / 'javac'), '-source', '8', '-target', '8',
            '-Xlint:-options', '-encoding', 'UTF-8', '-bootclasspath', str(platform),
            '-d', str(classes), str(source / 'SystemSettingsRepository.java'),
            str(source / 'NavigationAudioAdapter.java'),
            str(ROOT / 'app/native-tests/test-settings/SettingsProbe.java')], check=True)
        subprocess.run([str(java / 'java'), '-cp', str(sdk / 'cmdline-tools/latest/lib/r8.jar'),
            'com.android.tools.r8.D8', '--min-api', '24', '--lib', str(platform),
            '--output', str(dex), *map(str, classes.rglob('*.class'))], check=True)
        print('PASS: Android API 28 compilation and D8')
        if not args.serial:
            return
        adb = ['adb', '-s', args.serial]
        # Unique remote path; only this probe's own dex is removed on exit.
        remote = '/data/local/tmp/' + temp.name + '.dex'
        pushed = False
        try:
            subprocess.run([*adb, 'push', str(dex / 'classes.dex'), remote],
                check=True, capture_output=True, timeout=30)
            pushed = True
            result = subprocess.run([*adb, 'shell', 'env', 'CLASSPATH=' + remote,
                'app_process', '/system/bin', 'SettingsProbe'],
                check=True, text=True, capture_output=True, timeout=45)
            if 'NATIVE_TEST_PASS entries=' not in result.stdout:
                raise RuntimeError('Settings probe did not complete')
            if args.out:
                args.out.parent.mkdir(parents=True, exist_ok=True)
                args.out.write_text(result.stdout)
            print('\n'.join(line for line in result.stdout.splitlines()
                if line.startswith(('NATIVE_TEST_PASS', 'OEM_CLASS=', 'CAR_AUDIO_API='))))
        finally:
            if pushed:
                cleanup = subprocess.run([*adb, 'shell', 'rm', '-f', remote],
                    capture_output=True, timeout=15)
                if cleanup.returncode:
                    print('Probe cleanup pending on device: ' + remote)

if __name__ == '__main__':
    main()
