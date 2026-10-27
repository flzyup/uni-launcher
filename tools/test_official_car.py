#!/usr/bin/env python3
"""Offline official-car regressions and Android compilation. Never uses ADB/network."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration'
TESTS = ROOT / 'app/native-tests/test-official-car/xyz/i4o/uni/launcher/integration'


def executable(explicit, name):
    candidates = [explicit]
    if os.environ.get('JAVA_HOME'):
        candidates.append(str(Path(os.environ['JAVA_HOME']) / 'bin' / name))
    candidates.extend([shutil.which(name),
        str(Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin') / name)])
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return Path(candidate).resolve()
    raise SystemExit(f'{name} not found. Install JDK 17 or pass --{name}.')


def android_jar(explicit):
    if explicit:
        path = Path(explicit).expanduser().resolve()
        if not path.is_file():
            raise SystemExit(f'Android platform jar not found: {path}')
        return path
    roots = [os.environ.get('ANDROID_HOME'), os.environ.get('ANDROID_SDK_ROOT'),
             '/data/tools/linkco-android/sdk', str(Path.home() / 'Android/Sdk')]
    for sdk in roots:
        if not sdk:
            continue
        # The locally installed android-9 directory contains the audited API 28 platform.
        for platform in ['android-28', 'android-9']:
            path = Path(sdk) / 'platforms' / platform / 'android.jar'
            if path.is_file():
                return path.resolve()
    raise SystemExit('API 28 android.jar not found. Pass --android-jar PATH, or use '
                     '--skip-android-compile to run only pure JVM tests.')


def run(command):
    subprocess.run([str(item) for item in command], check=True, cwd=ROOT)


def validate(args, output):
    javac = executable(args.javac, 'javac')
    sibling_java = javac.parent / 'java'
    java = executable(args.java or (str(sibling_java) if sibling_java.is_file() else None), 'java')
    pure = [SOURCE / (name + '.java') for name in
            ['OfficialCarContract', 'OfficialCarPayload', 'OfficialCarCommand']]
    tests = [TESTS / (name + '.java') for name in ['OfficialCarPayloadTest', 'OfficialCarCommandTest']]
    test_output = output / 'jvm-tests'
    test_output.mkdir(parents=True, exist_ok=True)
    print('Running offline PA decoding and command-planning regressions', flush=True)
    run([javac, '--release', '8', '-encoding', 'UTF-8', '-d', test_output, *pure, *tests])
    for name in ['OfficialCarPayloadTest', 'OfficialCarCommandTest']:
        run([java, '-cp', test_output, 'xyz.i4o.uni.launcher.integration.' + name])
    if not args.skip_android_compile:
        platform = android_jar(args.android_jar)
        compiled = output / 'android-classes'
        compiled.mkdir(parents=True, exist_ok=True)
        print(f'Compiling all official-car helpers against {platform}', flush=True)
        run([javac, '-source', '8', '-target', '8', '-Xlint:-options', '-encoding', 'UTF-8',
             '-bootclasspath', platform, '-d', compiled, SOURCE / 'VehicleAdapter.java',
             *pure, SOURCE / 'OfficialCarReader.java', SOURCE / 'OfficialVehicleSensors.java',
             SOURCE / 'OfficialHybridReader.java', TESTS / 'OfficialHybridReaderTest.java',
             TESTS / 'OfficialVehicleSensorsTest.java'])
        run([java, '-cp', os.pathsep.join([str(compiled), str(platform)]),
             'xyz.i4o.uni.launcher.integration.OfficialVehicleSensorsTest'])
        run([java, '-cp', os.pathsep.join([str(compiled), str(platform)]),
             'xyz.i4o.uni.launcher.integration.OfficialHybridReaderTest'])
    print('Official-car local validation passed; no device access or vehicle commands.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--javac', help='JDK 17 javac executable')
    parser.add_argument('--java', help='JDK java executable; defaults to the javac sibling')
    parser.add_argument('--android-jar', help='Android API 28 platform jar')
    parser.add_argument('--skip-android-compile', action='store_true', help='Run pure JVM regressions only')
    parser.add_argument('--output-dir', type=Path, help='Keep compiled classes in this directory')
    args = parser.parse_args()
    if args.output_dir:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        validate(args, args.output_dir.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='lynk-official-car-tests-') as temporary:
            validate(args, Path(temporary))


if __name__ == '__main__':
    main()
