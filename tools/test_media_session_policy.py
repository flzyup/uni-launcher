#!/usr/bin/env python3
"""Offline media selection and paused metadata regressions; no vehicle access."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
jdk = Path(os.environ.get('JAVA_HOME', '/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64')) / 'bin'
core = root / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/core'
test = root / 'app/native-tests/test/xyz/i4o/uni/launcher/core/MediaSessionPolicyTest.java'
with tempfile.TemporaryDirectory(prefix='uni-media-policy-') as output:
    subprocess.run([str(jdk / 'javac'), '--release', '8', '-encoding', 'UTF-8', '-d', output,
                    str(core / 'MediaSourcePolicy.java'), str(core / 'MediaTextRetention.java'), str(test)], check=True)
    subprocess.run([str(jdk / 'java'), '-cp', output,
                    'xyz.i4o.uni.launcher.core.MediaSessionPolicyTest'], check=True)
