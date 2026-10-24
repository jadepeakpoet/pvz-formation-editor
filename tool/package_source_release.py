"""Archive the reviewed Git commit for a GitHub release."""
from pathlib import Path
import argparse
import hashlib
import re
import subprocess
import zipfile

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ref', default='HEAD', help='Reviewed release commit or tag')
args = parser.parse_args()
commit = subprocess.check_output(['git', 'rev-parse', '--verify', args.ref+'^{commit}'], cwd=repo, text=True).strip()
spec = subprocess.check_output(['git', 'show', commit+':pubspec.yaml'], cwd=repo, text=True, encoding='utf-8')
version = re.search(r'^version: (\d+\.\d+\.\d+)', spec, re.M).group(1)
root = repo/'release'/version
root.mkdir(parents=True, exist_ok=True)
name = f'PvZ-Formation-Editor-{version}-source'
archive = root/(name+'.zip')
subprocess.run(['git', 'archive', '--format=zip', '--prefix='+name+'/', '--output='+str(archive), commit], cwd=repo, check=True)
with zipfile.ZipFile(archive) as check:
    assert check.testzip() is None
    names = check.namelist()
    for required in ['LICENSE', 'pubspec.lock', 'lib/main.dart', 'windows/runner/game_bridge.cpp', 'assets/original/manifest.json']:
        assert name+'/'+required in names, required
    for entry in names:
        path = Path(entry)
        assert not any(part in ['.git', '.wrangler', '.pub-cache', '.local-tools', 'release', 'build'] for part in path.parts), entry
        assert not path.name.startswith(('.env', '.admin-password')), entry
checksums = [hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.name for file in sorted(root.glob('*.zip'))]
(root/'SHA256SUMS.txt').write_text('\n'.join(checksums)+'\n', encoding='ascii')
print(f'{archive}: {archive.stat().st_size} bytes; commit {commit}')
