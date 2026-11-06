#!/usr/bin/env python3
"""构建「UNI 无线 adb 桥」这个小 APK：aapt2 打包 → javac → d8 → zipalign → 平台签名。

它必须用平台证书签名，并在清单里声明 sharedUserId=android.uid.system，
装到 /data/app 后 uid 就是 1000，才能写 service.adb.tcp.port 和 ctl.restart。

用法：
  python tools/build_adb_bridge.py --toolchain D:\\PO\\signing\\ip753
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PROJECT = REPO / 'android-helper' / 'adb-bridge'
BUILD = REPO / 'android-helper' / 'build'
SLOT = 'xyz.i4o.uni.adbbridge'


def find_sdk(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    for candidate in (Path('E:/Android/Sdk'), Path.home() / 'AppData/Local/Android/Sdk'):
        if (candidate / 'platforms').is_dir():
            return candidate
    raise SystemExit('找不到 Android SDK，请用 --sdk 指定')


def newest(folder: Path, name: str) -> Path:
    items = sorted(folder.glob(name))
    if not items:
        raise SystemExit(f'{folder} 下没有 {name}')
    return items[-1]


def run(command: list[str], what: str) -> None:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr)
        raise SystemExit(f'{what} 失败（退出码 {result.returncode}）')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--sdk', default=None)
    parser.add_argument('--toolchain', type=Path, default=REPO / 'signing' / 'ip753')
    args = parser.parse_args()

    sdk = find_sdk(args.sdk)
    build_tools = newest(sdk / 'build-tools', '*')
    android_jar = sdk / 'platforms' / 'android-28' / 'android.jar'
    if not android_jar.is_file():
        raise SystemExit(f'缺少 {android_jar}')
    aapt2 = next((p for p in (build_tools / 'aapt2', build_tools / 'aapt2.exe') if p.is_file()), None)
    d8 = next((p for p in (build_tools / 'd8', build_tools / 'd8.bat') if p.is_file()), None)
    zipalign = next((p for p in (build_tools / 'zipalign', build_tools / 'zipalign.exe') if p.is_file()), None)
    apksigner = build_tools / 'lib' / 'apksigner.jar'
    if not aapt2 or not d8 or not zipalign or not apksigner.is_file():
        raise SystemExit(f'{build_tools} 里缺 aapt2/d8/zipalign/apksigner')

    keys = args.toolchain
    pem, pk8 = keys / 'platform.x509.pem', keys / 'platform.pk8'
    if not pem.is_file() or not pk8.is_file():
        raise SystemExit(f'{keys} 里没有 platform.x509.pem / platform.pk8')

    if BUILD.exists():
        for child in ('gen', 'classes', 'dex'):
            shutil.rmtree(BUILD / child, ignore_errors=True)
    (BUILD / 'gen').mkdir(parents=True, exist_ok=True)
    (BUILD / 'classes').mkdir(parents=True, exist_ok=True)
    (BUILD / 'dex').mkdir(parents=True, exist_ok=True)

    unsigned = BUILD / 'adb-bridge-unsigned.apk'
    if unsigned.exists():
        unsigned.unlink()
    run([str(aapt2), 'link', '--manifest', str(PROJECT / 'AndroidManifest.xml'),
         '-I', str(android_jar), '-o', str(unsigned), '--java', str(BUILD / 'gen')],
        'aapt2 link')

    sources = sorted(str(p) for p in (PROJECT / 'src').rglob('*.java'))
    java = shutil.which('javac')
    if java is None:
        raise SystemExit('找不到 javac')
    run([java, '-nowarn', '-source', '8', '-target', '8', '-encoding', 'UTF-8',
         '-bootclasspath', str(android_jar), '-d', str(BUILD / 'classes')] + sources,
        'javac')

    classes = [str(p) for p in (BUILD / 'classes').rglob('*.class')]
    run([str(d8), '--lib', str(android_jar), '--min-api', '23',
         '--output', str(BUILD / 'dex')] + classes, 'd8')

    staged = BUILD / 'adb-bridge-staged.apk'
    if staged.exists():
        staged.unlink()
    shutil.copy2(unsigned, staged)
    with zipfile.ZipFile(staged, 'a', zipfile.ZIP_DEFLATED) as archive:
        archive.write(BUILD / 'dex' / 'classes.dex', 'classes.dex')

    aligned = BUILD / 'adb-bridge-aligned.apk'
    if aligned.exists():
        aligned.unlink()
    run([str(zipalign), '-f', '-p', '4', str(staged), str(aligned)], 'zipalign')

    signed = BUILD / 'adb-bridge-signed.apk'
    if signed.exists():
        signed.unlink()
    run([sys.executable, '-c', 'import sys;print(sys.executable)'], 'python')
    java_bin = shutil.which('java')
    if java_bin is None:
        raise SystemExit('找不到 java')
    run([java_bin, '-cp', str(apksigner), 'com.android.apksigner.ApkSignerTool', 'sign',
         '--key', str(pk8), '--cert', str(pem),
         '--min-sdk-version', '23', '--v1-signing-enabled', 'true',
         '--out', str(signed), str(aligned)], 'apksigner')

    dist = REPO / 'dist'
    dist.mkdir(exist_ok=True)
    target = dist / 'UNI-AdbBridge-1.0-IP753.apk'
    shutil.copy2(signed, target)
    print(f'APK: {target}')
    print(f'package: {SLOT}')


if __name__ == '__main__':
    main()
