#!/usr/bin/env python3
"""Offline door signal mapping and unverified-value regression."""
from pathlib import Path
import subprocess
import tempfile
from test_official_car import executable

root = Path(__file__).resolve().parents[1]
javac = executable(None, 'javac')
java = executable(str(javac.parent / 'java'), 'java')
jars = sorted((Path.home() / '.gradle/caches/modules-2/files-2.1/org.json/json').glob('*/*/json-*.jar'))
if not jars:
    raise SystemExit('org.json test dependency not found in Gradle cache')
with tempfile.TemporaryDirectory(prefix='uni-body-') as directory:
    subprocess.run([str(javac), '--release', '8', '-cp', str(jars[-1]), '-d', directory,
                    str(root / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/OfficialBodySignals.java'),
                    str(root / 'app/native-tests/test/xyz/i4o/uni/launcher/integration/OfficialBodySignalsTest.java')], check=True)
    subprocess.run([str(java), '-cp', f'{directory}:{jars[-1]}',
                    'xyz.i4o.uni.launcher.integration.OfficialBodySignalsTest'], check=True)
