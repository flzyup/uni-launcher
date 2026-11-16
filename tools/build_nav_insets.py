#!/usr/bin/env python3
"""Build the code-free Android 9 navigation inset resources; never enables them."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def build(target, sdk=None, platform='android-9'):
    sdk = Path(sdk) if sdk else Path('/data/tools/linkco-android/sdk')
    aapt = sdk / 'build-tools/36.0.0/aapt2'
    # 平台目录名在两种 SDK 安装方式下不同：有的按版本号叫 android-9，有的按
    # API 号叫 android-28。Android 9 就是 API 28，两者 android.jar 等价，
    # 编译出的资源一致，所以缺哪个就换另一个，别让签名流程卡在这里。
    platform_dir = sdk / 'platforms' / platform
    if not platform_dir.exists():
        alias = {'android-9': 'android-28', 'android-28': 'android-9'}.get(platform)
        if alias and (sdk / 'platforms' / alias).exists():
            platform_dir = sdk / 'platforms' / alias
    jar = platform_dir / 'android.jar'
    if not jar.exists():
        raise SystemExit(
            f'找不到 android.jar：试过 {sdk / "platforms" / platform}'
            f' 与等价的 API 目录。请用 sdkmanager 安装 platforms;android-28，'
            f'或用 --platform 指定一个已安装的平台。')
    with tempfile.TemporaryDirectory(prefix='uni-nav-insets-') as temp:
        compiled = Path(temp) / 'resources.zip'
        subprocess.run([str(aapt), 'compile', '--dir', str(ROOT / 'app/android/nav-insets/res'), '-o', str(compiled)], check=True)
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(aapt), 'link', '-I', str(jar),
            '--manifest', str(ROOT / 'app/android/nav-insets/AndroidManifest.xml'), '--auto-add-overlay', '--no-resource-deduping', '-o', str(target), '-R', str(compiled)], check=True)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--sdk', type=Path, default=None,
                   help='Android SDK root; the build-tools and platform come from it')
    p.add_argument('--platform', default='android-9',
                   help='platform folder under <sdk>/platforms (android-9 = API 28)')
    args = p.parse_args()
    build(args.out.resolve(), args.sdk, args.platform)
