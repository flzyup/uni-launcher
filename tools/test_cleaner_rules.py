#!/usr/bin/env python3
"""垃圾清理规则引擎的离线断言（不需要设备、不碰 ADB）。

编译 app 里的 `CleanerRules` 与 `CleanerRulesTest` 后直接跑 main；
只验证纯逻辑：路径合法性、glob、白名单优先与例外、扩展名/体积/年龄门槛、
扫描剪枝、未确认规则不默认勾选。
"""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/core/CleanerRules.java')
TEST = (ROOT / 'app/native-tests/test/xyz/i4o/uni/launcher/core/CleanerRulesTest.java')
MAIN = 'xyz.i4o.uni.launcher.core.CleanerRulesTest'

sys.path.insert(0, str(ROOT / 'tools'))
from test_official_car import executable  # noqa: E402  (共享 JDK 定位逻辑)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--javac', help='覆盖 javac 路径')
    parser.add_argument('--java', help='覆盖 java 路径')
    args = parser.parse_args()
    javac = executable(args.javac, 'javac')
    java = executable(args.java or str(javac.parent / 'java'), 'java')
    for path in (SOURCE, TEST):
        if not path.is_file():
            raise SystemExit(f'missing source: {path}')
    with tempfile.TemporaryDirectory(prefix='uni-cleaner-rules-') as directory:
        subprocess.run([str(javac), '--release', '17', '-encoding', 'UTF-8',
                        '-d', directory, str(SOURCE), str(TEST)], check=True)
        subprocess.run([str(java), '-cp', directory, MAIN], check=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
