#!/usr/bin/env python3
"""在车机/模拟器上采集存储事实，产出垃圾清理规则的核对清单。

只读：不删任何东西，不改系统设置。输出 `analysis/storage-probe-<日期>.json`，
其中每条候选路径的 `verified` 都是 false —— 实车确认后才允许把对应规则
在 `rules.json` 里标成 `verified: true`。

用法:
    python tools/probe_storage.py                 # 自动选第一台设备
    python tools/probe_storage.py -s <serial>
    python tools/probe_storage.py --out analysis/storage-probe.json
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

# 与 app/android/app/src/main/assets/cleaner/rules.json 一一对应：
# (逻辑路径, 归属规则 id, 期望形态)
CANDIDATES = [
    ('/sdcard/Android/data', 'external-cache', 'dir'),
    ('/sdcard/Android/obb', 'orphan-data', 'dir'),
    ('/sdcard/DCIM/.thumbnails', 'thumbnails', 'dir'),
    ('/sdcard/.thumbnails', 'thumbnails', 'dir'),
    ('/sdcard/Pictures/.thumbnails', 'thumbnails', 'dir'),
    ('/sdcard/LOST.DIR', 'log', 'dir'),
    ('/sdcard/.tmp', 'log', 'dir'),
    ('/sdcard/Download', 'apk-leftover', 'dir'),
    ('/sdcard/amapauto8', 'never:navi', 'dir'),
    ('/sdcard/amapauto9', 'never:navi', 'dir'),
    ('/sdcard/AMapAuto', 'never:navi', 'dir'),
    ('/sdcard/AutoNavi', 'never:navi', 'dir'),
    ('/sdcard/baidumap', 'never:navi', 'dir'),
    ('/sdcard/BaiduNavi', 'never:navi', 'dir'),
    ('/sdcard/tencent', 'never:navi', 'dir'),
    ('/sdcard/ota', 'never:ota', 'dir'),
    ('/sdcard/update.zip', 'never:ota', 'file'),
    ('/sdcard/Android/media', 'never:media', 'dir'),
]

# 大于这个体积的公开目录值得人看一眼（只是提示，不进默认规则）。
LARGE_DIR_BYTES = 200 * 1024 * 1024
# du 单条命令上限，避免某个巨大目录把脚本挂住。
DU_TIMEOUT = 20


def adb_path(explicit):
    if explicit:
        return explicit
    found = shutil.which('adb')
    if found:
        return found
    for base in (Path('E:/Android/Sdk'), Path.home() / 'Android/Sdk'):
        candidate = base / 'platform-tools' / ('adb.exe' if sys.platform == 'win32' else 'adb')
        if candidate.is_file():
            return str(candidate)
    raise SystemExit('adb not found; pass --adb or add platform-tools to PATH')


class Adb:
    def __init__(self, executable, serial=None):
        self.executable = executable
        self.serial = serial

    def _base(self):
        cmd = [self.executable]
        if self.serial:
            cmd += ['-s', self.serial]
        return cmd

    def shell(self, command, timeout=30):
        try:
            done = subprocess.run(self._base() + ['shell', command],
                                  capture_output=True, text=True,
                                  encoding='utf-8', errors='replace', timeout=timeout)
        except subprocess.TimeoutExpired:
            return ''
        if done.returncode != 0 and not done.stdout:
            return ''
        return done.stdout.replace('\r\n', '\n').replace('\r', '\n')

    def raw(self, args, timeout=30):
        try:
            done = subprocess.run(self._base() + args, capture_output=True, text=True,
                                  encoding='utf-8', errors='replace', timeout=timeout)
        except subprocess.TimeoutExpired:
            return ''
        return done.stdout


def parse_df(text):
    """`df -k` 的 POSIX 输出 → {挂载点: 字节数}。Android 的 df 列宽会变，用尾部对齐。"""
    volumes = {}
    for line in text.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 6:
            continue
        try:
            size, used, avail = int(parts[1]) * 1024, int(parts[2]) * 1024, int(parts[3]) * 1024
        except ValueError:
            continue
        mount = parts[-1]
        volumes[mount] = {'size': size, 'used': used, 'avail': avail}
    return volumes


def du_bytes(adb, path):
    """`du -sk` → 字节数；路径不存在返回 None。"""
    text = adb.shell(f'du -sk {path} 2>/dev/null', timeout=DU_TIMEOUT).strip()
    if not text:
        return None
    first = text.splitlines()[0].split()
    if not first:
        return None
    try:
        return int(first[0]) * 1024
    except ValueError:
        return None


def count_files(adb, path):
    text = adb.shell(f'ls -1A {path} 2>/dev/null | wc -l', timeout=DU_TIMEOUT).strip()
    try:
        return int(text.split()[-1])
    except (ValueError, IndexError):
        return 0


def top_dirs(adb, root='/sdcard', depth=2, limit=40):
    """`du -k -d N` 取占用最大的若干目录。iOS/Android 的 du 支持 -d。"""
    text = adb.shell(f'du -k -d {depth} {root} 2>/dev/null', timeout=60)
    rows = []
    for line in text.splitlines():
        parts = line.split('\t') if '\t' in line else line.split(None, 1)
        if len(parts) != 2:
            continue
        try:
            size = int(parts[0]) * 1024
        except ValueError:
            continue
        rows.append({'path': parts[1].strip(), 'bytes': size})
    rows.sort(key=lambda row: row['bytes'], reverse=True)
    return rows[:limit]


def packages(adb, flag):
    text = adb.shell(f'pm list packages {flag}'.strip(), timeout=60)
    return sorted(line.split(':', 1)[1].strip()
                  for line in text.splitlines() if line.startswith('package:'))


def external_caches(adb):
    """每个应用在公共存储里的 cache / code_cache，对应 external-cache 规则。"""
    text = adb.shell('du -sk /sdcard/Android/data/*/cache '
                     '/sdcard/Android/data/*/code_cache 2>/dev/null', timeout=120)
    rows = []
    for line in text.splitlines():
        parts = line.split('\t') if '\t' in line else line.split(None, 1)
        if len(parts) != 2:
            continue
        try:
            size = int(parts[0]) * 1024
        except ValueError:
            continue
        path = parts[1].strip()
        segments = path.split('/')
        rows.append({'path': path, 'bytes': size,
                     'package': segments[4] if len(segments) > 4 else ''})
    rows.sort(key=lambda row: row['bytes'], reverse=True)
    return rows[:60]


def orphan_dirs(adb, installed):
    """`/sdcard/Android/{data,obb}` 下的包名目录，而该包已经不在了 → 卸载残留。"""
    rows = []
    for parent in ('/sdcard/Android/data', '/sdcard/Android/obb'):
        text = adb.shell(f'ls -1 {parent} 2>/dev/null', timeout=60)
        for name in (line.strip() for line in text.splitlines()):
            if not name or '.' not in name or name in installed:
                continue
            path = f'{parent}/{name}'
            rows.append({'path': path, 'package': name, 'bytes': du_bytes(adb, path)})
    rows.sort(key=lambda row: row['bytes'] or 0, reverse=True)
    return rows[:60]


def apk_files(adb):
    """全盘安装包，对应 apk-leftover 规则（大小下限与 minSize 一致）。"""
    command = ("find /sdcard -type f \\( -name '*.apk' -o -name '*.apks' "
               "-o -name '*.xapk' -o -name '*.apkm' \\) -size +512k 2>/dev/null | head -60")
    text = adb.shell(command, timeout=120)
    return [{'path': line.strip(), 'bytes': du_bytes(adb, line.strip())}
            for line in text.splitlines() if line.strip()]


def empty_dirs(adb):
    """空目录样本，对应 empty-dir 规则；只统计数量与最深路径。"""
    text = adb.shell('find /sdcard -type d -empty 2>/dev/null | head -80', timeout=90)
    return [line.strip() for line in text.splitlines() if line.strip()]


def probe(adb):
    result = {
        'generatedAt': dt.datetime.now().astimezone().isoformat(timespec='seconds'),
        'serial': adb.serial or (adb.raw(['get-serialno'], timeout=10).strip() or 'unknown'),
        'android': {
            'release': adb.shell('getprop ro.build.version.release').strip(),
            'sdk': adb.shell('getprop ro.build.version.sdk').strip(),
            'model': adb.shell('getprop ro.product.model').strip(),
            'platform': adb.shell('getprop ro.board.platform').strip(),
            'build': adb.shell('getprop ro.build.display.id').strip(),
        },
        'volumes': parse_df(adb.shell('df -k /data /sdcard /storage/emulated 2>/dev/null')),
        'diskstats': adb.shell('dumpsys diskstats 2>/dev/null')[:4000],
        'sdcardRoot': [line for line in adb.shell('ls -1A /sdcard').splitlines() if line.strip()],
        'topDirs': top_dirs(adb),
        'packages': {'user': packages(adb, '-3'), 'system': packages(adb, '-s')},
        'candidates': [],
    }
    for path, rule, kind in CANDIDATES:
        exists = adb.shell(f'[ -e {path} ] && echo yes || echo no').strip() == 'yes'
        entry = {'path': path, 'rule': rule, 'kind': kind, 'exists': exists, 'verified': False}
        if exists:
            entry['bytes'] = du_bytes(adb, path)
            entry['entries'] = count_files(adb, path)
        result['candidates'].append(entry)
    # 全系统类目：外部缓存、卸载残留、全盘安装包、空目录。
    installed = set(packages(adb, ''))
    result['installedCount'] = len(installed)
    result['externalCaches'] = external_caches(adb)
    result['orphanDirs'] = orphan_dirs(adb, installed)
    result['apkFiles'] = apk_files(adb)
    result['emptyDirs'] = empty_dirs(adb)
    result['externalCacheBytes'] = sum(item['bytes'] for item in result['externalCaches'])
    result['orphanBytes'] = sum(item['bytes'] or 0 for item in result['orphanDirs'])
    result['apkBytes'] = sum(item['bytes'] or 0 for item in result['apkFiles'])
    # 公开目录里的大文件（只提示，不默认勾选）：给「长期未动的大文件」一个实车样本。
    result['largeFiles'] = []
    text = adb.shell('find /sdcard -type f -size +200M 2>/dev/null | head -40', timeout=120)
    for line in text.splitlines():
        path = line.strip()
        if path:
            result['largeFiles'].append({'path': path, 'bytes': du_bytes(adb, path)})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('-s', '--serial', help='设备序列号')
    parser.add_argument('--adb', help='adb 路径')
    parser.add_argument('--out', help='输出文件（默认 analysis/storage-probe-<日期>.json）')
    args = parser.parse_args()

    adb = Adb(adb_path(args.adb), args.serial)
    devices = [line.split('\t')[0] for line in adb.raw(['devices']).splitlines()[1:]
               if line.strip().endswith('device')]
    if not args.serial:
        if not devices:
            raise SystemExit('no device online; connect the car head unit or start an emulator')
        adb.serial = devices[0]
    out = Path(args.out) if args.out else (
        ROOT / 'analysis' / f"storage-probe-{dt.date.today():%Y%m%d}.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = probe(adb)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')

    found = [item for item in payload['candidates'] if item['exists']]
    print(f'wrote {out}')
    print(f"device: {payload['android']['model']} · Android {payload['android']['release']}"
          f" (API {payload['android']['sdk']})")
    for mount, stats in payload['volumes'].items():
        print(f"  {mount}: used {stats['used'] / 2**30:.1f}G / {stats['size'] / 2**30:.1f}G")
    print(f'candidates present: {len(found)}/{len(payload["candidates"])}')
    for item in found:
        size = item.get('bytes')
        label = f"{size / 2**20:.1f} MB" if size else 'n/a'
        print(f"  {item['path']}  [{item['rule']}]  {label}  entries={item.get('entries', 0)}")
    if payload['largeFiles']:
        print(f"large files: {len(payload['largeFiles'])}")
    print(f"外部缓存: {len(payload['externalCaches'])} 个目录 "
          f"{payload['externalCacheBytes'] / 2**20:.1f} MB")
    print(f"卸载残留: {len(payload['orphanDirs'])} 个目录 "
          f"{payload['orphanBytes'] / 2**20:.1f} MB")
    print(f"安装包: {len(payload['apkFiles'])} 个 {payload['apkBytes'] / 2**20:.1f} MB")
    print(f"空目录: {len(payload['emptyDirs'])} 个（最多列 80）")
    for item in payload['orphanDirs'][:10]:
        size = item.get('bytes') or 0
        print(f"  orphan {item['path']}  {size / 2**20:.1f} MB")
    print('每条候选的 verified 都是 false：确认后手工改 rules.json 再打包。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
