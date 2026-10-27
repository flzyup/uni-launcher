#!/usr/bin/env python3
"""Offline regression for district/city/province forecast matching."""
from pathlib import Path
import subprocess
import tempfile
from test_official_car import executable

root = Path(__file__).resolve().parents[1]
javac = executable(None, 'javac')
java = executable(str(javac.parent / 'java'), 'java')
with tempfile.TemporaryDirectory(prefix='uni-weather-') as directory:
    subprocess.run([str(javac), '--release', '8', '-encoding', 'UTF-8', '-d', directory,
                    str(root / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/WeatherLocationResolver.java'),
                    str(root / 'app/native-tests/test-weather/WeatherLocationResolverTest.java')], check=True)
    subprocess.run([str(java), '-cp', directory, 'WeatherLocationResolverTest'], check=True)
