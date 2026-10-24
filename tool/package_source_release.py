"""Package the corresponding v1.0.0 source without ignored build/user data."""
from pathlib import Path
import subprocess,zipfile,hashlib
repo=Path(__file__).resolve().parent.parent
result=subprocess.run(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=repo,capture_output=True,check=True)
paths=sorted(set(result.stdout.decode('utf-8').split('\0'))-set(['']))
root=repo/'release/1.0.0';root.mkdir(parents=True,exist_ok=True)
archive=root/'PvZ-Formation-Editor-1.0.0-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as out:
    for name in paths:
        file=(repo/name).resolve()
        assert file.is_relative_to(repo)
        if not file.is_file():continue
        assert not any(part in ['.git','.wrangler','.pub-cache','.local-tools','release','build'] for part in Path(name).parts),name
        assert not file.name.startswith('.env'),name
        out.write(file,'PvZ-Formation-Editor-1.0.0-source/'+name)
with zipfile.ZipFile(archive) as check:
    assert check.testzip() is None
    names=check.namelist()
    for required in ['LICENSE','pubspec.lock','lib/main.dart','windows/runner/game_bridge.cpp','assets/original/manifest.json']:
        assert 'PvZ-Formation-Editor-1.0.0-source/'+required in names,required
assert archive.stat().st_size<25*1024*1024,'Source exceeds Pages asset size limit'
print(archive,archive.stat().st_size,'bytes')
checksums=[]
for file in sorted(root.glob('*.zip')):
    checksums.append(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.name)
(root/'SHA256SUMS.txt').write_text('\n'.join(checksums)+'\n',encoding='ascii')
