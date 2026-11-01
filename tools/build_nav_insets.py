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
    with tempfile.TemporaryDirectory(prefix='uni-nav-insets-') as temp:
        compiled = Path(temp) / 'resources.zip'
        subprocess.run([str(aapt), 'compile', '--dir', str(ROOT / 'app/android/nav-insets/res'), '-o', str(compiled)], check=True)
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(aapt), 'link', '-I', str(sdk / 'platforms'/platform/'android.jar'),
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
