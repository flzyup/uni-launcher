#!/usr/bin/env python3
"""Upload an existing IP753 APK to a GitHub Release draft."""
import argparse
import hashlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, check=True, text=True,
                          capture_output=capture).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, help='已签名 APK；默认使用对应版本的 IP753 包')
    parser.add_argument('--prerelease', action='store_true', help='标记为预发布')
    parser.add_argument('--dry-run', action='store_true', help='只检查本地信息，不连接 GitHub')
    args = parser.parse_args()

    version_match = re.search(r'^version:\s*([^+\s]+)', (ROOT / 'app/pubspec.yaml').read_text(), re.M)
    if not version_match:
        parser.error('无法从 app/pubspec.yaml 读取版本')
    version = version_match.group(1)
    tag = 'v' + version
    apk = (args.apk or ROOT / f'app/build/app/outputs/flutter-apk/UNI-Launcher-{version}-IP753.apk').resolve()
    if not apk.is_file() or apk.suffix.lower() != '.apk':
        parser.error(f'APK 不存在: {apk}')
    changelog = (ROOT / 'CHANGELOG.md').read_text()
    match = re.search(r'^## ' + re.escape(version) + r'\s*\n(.*?)(?=^## |\Z)', changelog, re.M | re.S)
    if not match:
        parser.error(f'CHANGELOG.md 缺少 {version} 的更新日志')
    commit = run('git', 'rev-parse', 'HEAD', capture=True).strip()
    with apk.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
        digest = digest.hexdigest()
    checksum = f'{digest}  {apk.name}\n'
    print(f'版本: {tag}\n提交: {commit}\nAPK: {apk}\nSHA-256: {digest}', flush=True)
    print('请确认 APK 由上述提交构建且签名正确；脚本无法验证构建来源。', flush=True)
    if args.dry_run:
        print('本地检查完成，未连接 GitHub。')
        return
    if not shutil.which('gh'):
        parser.error('未找到 GitHub CLI：请先安装 gh 并执行 gh auth login')
    run('gh', 'auth', 'status')
    # Fail closed if the commit is absent remotely or an existing tag points elsewhere.
    run('gh', 'api', f'repos/{{owner}}/{{repo}}/commits/{commit}', '--silent')
    refs = run('git', 'ls-remote', '--tags', 'origin', f'refs/tags/{tag}',
               f'refs/tags/{tag}^{{}}', capture=True).strip().splitlines()
    if refs:
        remote = {line.split('\t', 1)[1]: line.split('\t', 1)[0] for line in refs}
        target = remote.get(f'refs/tags/{tag}^{{}}', remote.get(f'refs/tags/{tag}'))
        if target != commit:
            parser.error(f'远程标签 {tag} 指向其他提交，请检查后再发布')
    with tempfile.TemporaryDirectory(prefix='uni-release-') as tmp:
        folder = Path(tmp)
        sums = folder / 'SHA256SUMS.txt'
        sums.write_text(checksum)
        notes = folder / 'notes.md'
        notes.write_text(match.group(1).strip() + '\n\nAPK SHA-256: `' + digest + '`\n')
        command = ['gh', 'release', 'create', tag, str(apk), str(sums), '--draft',
                   '--target', commit, '--title', f'UNI桌面 {tag}', '--notes-file', str(notes)]
        if args.prerelease:
            command.append('--prerelease')
        run(*command)
    print('Release 草稿已创建；请在 GitHub 检查后发布。')


if __name__ == '__main__':
    main()
