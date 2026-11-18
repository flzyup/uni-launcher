#!/usr/bin/env python3
"""Offline simulation routing regression. No device changes."""
import subprocess
import tempfile
from pathlib import Path
from test_official_car import executable

root = Path(__file__).resolve().parents[1]
javac = executable(None, 'javac')
with tempfile.TemporaryDirectory(prefix='uni-simulation-') as out:
    subprocess.run([str(javac), '--release', '8', '-d', out,
        str(root/'app/android/app/src/main/java/xyz/i4o/uni/launcher/core/SimulationMode.java'),
        str(root/'app/native-tests/test/xyz/i4o/uni/launcher/core/SimulationModeTest.java')], check=True)
    subprocess.run([str(javac.parent/'java'), '-cp', out,
        'xyz.i4o.uni.launcher.core.SimulationModeTest'], check=True)
