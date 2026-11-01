#!/usr/bin/env python3
"""Create a separate IP753 test APK using the owner's existing local signing files.

Does not install, change UID, or include any key in the source repository.
The regular emulator/development APK retains its own certificate.
"""
import argparse
import hashlib
import os
import subprocess
import tempfile
import shutil
import zipfile
from pathlib import Path
from build_nav_insets import build as build_nav_insets

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', required=True, type=Path)
parser.add_argument('--out', type=Path, default=None,
                    help='where to write the signed APK; defaults to '
                         'dist/UNI-Launcher-<version>-IP753.apk next to this '
                         'repository. The car packages live in dist/ so they '
                         'never mix with the raw build output, where several '
                         'stale APKs used to sit and get installed by mistake.')
parser.add_argument('--toolchain', type=Path, default=None,
                    help='directory that holds platform.pk8 and platform.x509.pem')
parser.add_argument('--java', type=Path, default=None,
                    help='java launcher used to run apksigner')
parser.add_argument('--apksigner', type=Path, default=None,
                    help='apksigner.jar; taken from the SDK build-tools when omitted')
parser.add_argument('--sdk', type=Path, default=None,
                    help='Android SDK root used for apksigner and the nav insets')
args = parser.parse_args()
source = args.input.resolve()
target = args.out.resolve() if args.out else None
if target is not None and source == target:
    parser.error('Choose a separate output APK; preserve the development artifact')

# The repository root: <repo>/tools/sign_car_apk.py -> <repo>
REPO = Path(__file__).resolve().parent.parent
WORKSPACE = REPO.parent


def first_file(candidates, what):
    """The first existing candidate, or None."""
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.is_file():
            return path
    raise SystemExit(
        'Cannot find ' + what + '. Tried:\n  ' +
        '\n  '.join(str(c) for c in candidates if c))


def first_dir(candidates, what):
    """The first existing directory, or None."""
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.is_dir():
            return path
    raise SystemExit(
        'Cannot find ' + what + '. Tried:\n  ' +
        '\n  '.join(str(c) for c in candidates if c))


# -- The platform key -------------------------------------------------------
#
# The car only grants `android.car.permission.CAR_VENDOR_EXTENSION` to apps
# signed with **its own** platform certificate. That certificate is the AOSP
# platform key, and the fingerprint below is checked on every signature — a
# package signed with anything else simply does not get the permission.
#
# The key is kept outside Git. The sibling `cardesk` project uses the very
# same key for its platform build, so that directory is a valid source too.
toolchain = first_dir([
    args.toolchain,
    os.environ.get('IP753_SIGNING_DIR'),
    '/data/tools/linkco-android/ip753-signing',
    WORKSPACE / 'cardesk' / 'platform-key',
], 'the platform key directory (platform.pk8 + platform.x509.pem)')
key = toolchain / 'platform.pk8'
cert = toolchain / 'platform.x509.pem'
for path in (key, cert):
    if not path.is_file():
        parser.error('Missing local input: ' + str(path))

# -- The Java that runs apksigner ------------------------------------------
java = first_file([
    args.java,
    Path(os.environ.get('JAVA_HOME', '')) / 'bin' / 'java' if os.environ.get('JAVA_HOME') else None,
    shutil.which('java'),
    '/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin/java',
    WORKSPACE / 'toolchain' / 'jdk-17.0.20.1+1' / 'Contents' / 'Home' / 'bin' / 'java',
], 'a Java launcher for apksigner')

# -- The Android SDK (apksigner + the nav insets) ---------------------------
sdk = first_dir([
    args.sdk,
    os.environ.get('ANDROID_HOME'),
    os.environ.get('ANDROID_SDK_ROOT'),
    '/data/tools/linkco-android/sdk',
    WORKSPACE / 'toolchain' / 'sdk',
], 'the Android SDK root')

# -- apksigner --------------------------------------------------------------
jar = None
if args.apksigner:
    jar = Path(args.apksigner).expanduser()
    if not jar.is_file():
        parser.error('Missing local input: ' + str(jar))
else:
    build_tools = sorted((sdk / 'build-tools').glob('*'), reverse=True)
    for folder in build_tools:
        candidate = folder / 'lib' / 'apksigner.jar'
        if candidate.is_file():
            jar = candidate
            break
    if jar is None:
        parser.error('No apksigner.jar under ' + str(sdk / 'build-tools'))

for path in [source, java, jar, key, cert]:
    if not path.is_file():
        parser.error('Missing local input: ' + str(path))


def apk_badging(apk):
    """(versionName, versionCode) of an APK, or (None, None)."""
    for folder in sorted((sdk / 'build-tools').glob('*'), reverse=True):
        aapt2 = folder / 'aapt2'
        if not aapt2.is_file():
            continue
        try:
            out = subprocess.run([str(aapt2), 'dump', 'badging', str(apk)],
                                 check=True, capture_output=True, text=True).stdout
        except (OSError, subprocess.CalledProcessError):
            continue
        name = code = None
        for line in out.splitlines():
            if line.startswith('package:'):
                for part in line.split():
                    if part.startswith('versionName='):
                        name = part.split('=', 1)[1].strip("'")
                    elif part.startswith('versionCode='):
                        code = part.split('=', 1)[1].strip("'")
                break
        return name, code
    return None, None


version, version_code = apk_badging(source)
if target is None:
    # The default keeps every car package in dist/, the same place cardesk
    # puts its own. The version comes from the APK that was just built, so
    # the file name cannot drift away from what is actually inside it.
    target = (REPO / 'dist' /
              ('UNI-Launcher-' + (version or 'unknown') + '-IP753.apk')).resolve()

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
digest = hashlib.sha256(target.read_bytes()).hexdigest()

# -- dist/README.md ---------------------------------------------------------
#
# The car package used to sit next to the raw build output, where a handful
# of stale APKs of nearly the same size made it easy to install the wrong
# one. cardesk solves this by writing the same kind of README next to its
# own package; do the same here so the file to install is unambiguous.
readme = target.parent / 'README.md'
if target.parent == REPO / 'dist':
    others = sorted(p.name for p in target.parent.glob('*.apk')
                    if p.name != target.name)
    lines = [
        '# dist/ 交付说明',
        '',
        '> 本文件由 `tools/sign_car_apk.py` **自动生成**。',
        '',
        '## 当前版本',
        '',
        '| 文件 | 包名 | versionCode | versionName | 签名 | SHA-256 |',
        '| --- | --- | --- | --- | --- | --- |',
        '| `' + target.name + '` | `xyz.i4o.uni.launcher` | **'
        + str(version_code or '?') + '** | `' + str(version or '?')
        + '` | AOSP platform 签名 | `' + digest + '` |',
        '',
        '> 这是**唯一需要安装**的包。装到车机后重启桌面。',
        '',
        '## 目录里其它 APK',
        '',
        '| 文件 | 说明 |',
        '| --- | --- |',
    ]
    for name in others:
        # A file with "-ab-" in its name is an A/B build kept on purpose (the
        # owner compares two builds on the car). Marking it as "do not
        # install" would be wrong, so it gets its own row.
        if '-ab-' in name:
            lines.append('| `' + name + '` | **A/B 对照包**，按需要自选 |')
        else:
            lines.append('| `' + name + '` | 旧包，**不要装** |')
    if not others:
        lines.append('| — | 目录里没有其它 APK |')
    lines.append('')
    readme.write_text('\n'.join(lines), encoding='utf-8')

print('Verified IP753 certificate SHA-256:', expected)
print('APK:', target)
print('APK SHA-256:', digest)
