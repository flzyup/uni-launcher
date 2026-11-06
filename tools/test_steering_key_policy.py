#!/usr/bin/env python3
"""Offline steering-wheel / center-panel key mapping regressions; no vehicle access."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
jdk = Path(os.environ.get('JAVA_HOME', '/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64')) / 'bin'
core = root / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/core'
test = root / 'app/native-tests/test/xyz/i4o/uni/launcher/core/SteeringKeyPolicyTest.java'
with tempfile.TemporaryDirectory(prefix='uni-steering-keys-') as output:
    subprocess.run([str(jdk / 'javac'), '--release', '8', '-encoding', 'UTF-8', '-d', output,
                    str(core / 'SteeringKeyPolicy.java'), str(test)], check=True)
    subprocess.run([str(jdk / 'java'), '-cp', output,
                    'xyz.i4o.uni.launcher.core.SteeringKeyPolicyTest'], check=True)
