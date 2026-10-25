"""Split a verified universal macOS Release app into signed arm64/x64 ZIPs."""
from pathlib import Path
import argparse
import hashlib
import plistlib
import re
import subprocess
import tempfile
import zipfile

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(__doc__)
parser.add_argument('--build', type=Path, required=True, help='Verified universal Release .app')
args = parser.parse_args()
version = re.search(r'^version: (\d+\.\d+\.\d+)', (repo / 'pubspec.yaml').read_text(), re.M)[1]
source = args.build.resolve()
assert source.suffix == '.app' and source.is_dir(), 'Expected a Release .app'
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == version, 'Bundle version mismatch'
assert info['CFBundleIdentifier'] == 'com.xiaomeng.pvz.formation.macos', 'Bundle ID mismatch'
source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
release = repo / 'release' / version
release.mkdir(parents=True, exist_ok=True)


def run(*command):
    try:
        return subprocess.check_output([str(x) for x in command], stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(error.output.decode(errors='replace')) from error


for label, arch in [('arm64', 'arm64'), ('x64', 'x86_64')]:
    with tempfile.TemporaryDirectory(prefix='pvz-macos-package-') as temp:
        stage = Path(temp) / f'PvZ-Formation-Editor-{version}-macos-{label}'
        stage.mkdir()
        app = stage / source.name
        run('ditto', source, app)
        run('xattr', '-cr', app)
        # Work on copies only; preserve framework symlinks and resource bundles.
        binaries = []
        for path in sorted(app.rglob('*')):
            if path.is_symlink() or not path.is_file():
                continue
            if 'Mach-O' not in run('file', '-b', path).decode():
                continue
            architectures = run('lipo', '-archs', path).decode().split()
            assert arch in architectures, f'{path}: missing {arch}'
            if len(architectures) > 1:
                thin = path.with_name(path.name + '.thin')
                run('lipo', path, '-thin', arch, '-output', thin)
                thin.chmod(path.stat().st_mode)
                thin.replace(path)
            binaries.append(path)
        assert binaries, 'No Mach-O binaries found'
        for path in binaries:
            run('codesign', '--force', '--sign', '-', path)
        # Sign nested frameworks before the enclosing app. Use Release entitlements,
        # excluding the development get-task-allow entitlement from the input build.
        for framework in sorted(app.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True):
            run('codesign', '--force', '--sign', '-', framework)
        run('codesign', '--force', '--sign', '-', '--entitlements',
            repo / 'macos/Runner/Release.entitlements', app)
        run('codesign', '--verify', '--deep', '--strict', app)
        for path in binaries:
            assert run('lipo', '-archs', path).decode().strip() == arch
            signature = run('codesign', '-dv', path).decode()
            assert 'Signature=adhoc' in signature and 'Authority=' not in signature, 'Expected anonymous ad-hoc signing'
        for name in ['LICENSE', 'ACKNOWLEDGMENTS.md']:
            run('ditto', repo / name, stage / name)
        (stage / 'SOURCE.txt').write_text(
            f'Source commit: {source_commit}\n'
            f'https://github.com/jadepeakpoet/pvz-formation-editor/tree/{source_commit}\n', encoding='ascii')
        (stage / 'README.txt').write_text(
            f'PVZ Formation Editor {version} — macOS {label}\n\n'
            'Requires macOS 12 or later. Extract the ZIP and drag the app to Applications.\n'
            'Apple Silicon: arm64; Intel: x64.\n'
            'This build is ad-hoc signed, without Developer ID signing or Apple notarization.\n'
            'After verifying the download source and SHA-256, if macOS blocks opening,\n'
            'use System Settings > Privacy & Security > Open Anyway (when offered).\n'
            'Installation help: https://xmpvz.pages.dev/en/docs/#macos\n'
            'Live PvZ game integration is available on Windows only.\n\n'
            '需要 macOS 12 或更新版本。解压后将应用拖入“应用程序”。\n'
            '本包采用本地签名，未经 Apple 公证；确认来源及校验值后，若系统阻止打开，\n'
            '可在“系统设置 > 隐私与安全”中使用“仍要打开”（若系统提供）。\n'
            '安装说明：https://xmpvz.pages.dev/docs/#macos\n'
            '游戏读取/应用等游戏接入功能仅适用于 Windows。\n', encoding='utf-8')
        archive = release / (stage.name + '.zip')
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', stage, archive)
        with zipfile.ZipFile(archive) as z:
            assert z.testzip() is None, 'ZIP CRC failure'
        print(f'{archive.name}: {len(binaries)} {arch} binaries; signature and ZIP verified; '
              f'{archive.stat().st_size} bytes; SHA256 {hashlib.sha256(archive.read_bytes()).hexdigest()}')
(release / 'SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n'
    for p in sorted(release.glob('*.zip'))), encoding='ascii')
