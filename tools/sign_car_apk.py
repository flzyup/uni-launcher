#!/usr/bin/env python3
"""Create a separate IP753 test APK using the owner's existing local signing files.

Does not install, change UID, or include any key in the source repository.
The regular emulator/development APK retains its own certificate.
"""
import argparse
import hashlib
import subprocess
import tempfile
import shutil
import zipfile
from pathlib import Path
from build_nav_insets import build as build_nav_insets

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--toolchain', type=Path, default=Path('/data/tools/linkco-android/ip753-signing'))
parser.add_argument('--java', type=Path, default=None,
                    help='java launcher used to run apksigner')
parser.add_argument('--apksigner', type=Path, default=None,
                    help='apksigner.jar; taken from the SDK build-tools when omitted')
parser.add_argument('--sdk', type=Path, default=None,
                    help='Android SDK root used for apksigner and the nav insets')
args = parser.parse_args()
source = args.input.resolve()
target = args.out.resolve()
if source == target:
    parser.error('Choose a separate output APK; preserve the development artifact')
toolchain = args.toolchain.resolve()
sdk = args.sdk.resolve() if args.sdk else Path('/data/tools/linkco-android/sdk')
java = args.java.resolve() if args.java else Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin/java')
if not java.is_file(): java = toolchain / 'root/usr/lib/jvm/java-17-openjdk-amd64/bin/java'
jar = args.apksigner.resolve() if args.apksigner else sdk / 'build-tools/36.0.0/lib/apksigner.jar'
key = toolchain / 'platform.pk8'
cert = toolchain / 'platform.x509.pem'
for path in [source, java, jar, key, cert]:
    if not path.is_file():
        parser.error('Missing local input: ' + str(path))
target.parent.mkdir(parents=True, exist_ok=True)
signer = [str(java), '-cp', str(jar), 'com.android.apksigner.ApkSignerTool']
with tempfile.TemporaryDirectory(prefix='uni-car-sign-') as temp:
    temp=Path(temp)
    with zipfile.ZipFile(source) as apk:
        launcher='assets/flutter_assets/AssetManifest.bin' in apk.namelist()
    signing_source=source
    if launcher:
        resource=temp/'insets-unsigned.apk'
        build_nav_insets(resource, sdk)
        signed_resource=temp/'insets.apk'
        subprocess.run([*signer,'sign','--key',str(key),'--cert',str(cert),
            '--v4-signing-enabled','false','--out',str(signed_resource),str(resource)],check=True)
        signing_source=temp/'launcher.apk'
        shutil.copyfile(source,signing_source)
        with zipfile.ZipFile(signing_source,'a',zipfile.ZIP_DEFLATED) as apk:
            apk.write(signed_resource,'assets/uni-nav-insets.apk')
    subprocess.run([*signer, 'sign', '--key', str(key), '--cert', str(cert),
                '--v1-signing-enabled', 'true', '--v2-signing-enabled', 'true',
                '--v3-signing-enabled', 'false', '--v4-signing-enabled', 'false',
                '--out', str(target), str(signing_source)], check=True)
verified = subprocess.run([*signer, 'verify', '--print-certs', str(target)],
                          check=True, capture_output=True, text=True).stdout
expected = 'c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8'
if 'certificate SHA-256 digest: ' + expected not in verified:
    target.unlink()
    raise SystemExit('Certificate does not match the verified IP753 test target')
print('Verified IP753 certificate SHA-256:', expected)
print('APK:', target)
print('APK SHA-256:', hashlib.sha256(target.read_bytes()).hexdigest())
