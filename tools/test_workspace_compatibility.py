#!/usr/bin/env python3
"""Test selection for the per-app workspace workaround without a device."""
from pathlib import Path
import subprocess
import tempfile
from test_official_car import executable

root = Path(__file__).resolve().parents[1]
javac = executable(None, 'javac')
java = executable(str(javac.parent / 'java'), 'java')
with tempfile.TemporaryDirectory(prefix='uni-workspace-') as directory:
    subprocess.run([str(javac), '--release', '8', '-d', directory,
                    str(root / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/overlay/WorkspaceCompatibilityPolicy.java'),
                    str(root / 'app/native-tests/test/xyz/i4o/uni/launcher/overlay/WorkspaceCompatibilityPolicyTest.java')], check=True)
    subprocess.run([str(java), '-cp', directory,
                    'xyz.i4o.uni.launcher.overlay.WorkspaceCompatibilityPolicyTest'], check=True)
