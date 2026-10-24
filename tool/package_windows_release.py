"""Create the complete Windows x64 ZIP, including app-local MSVC runtimes."""
from pathlib import Path
import argparse, shutil, zipfile, hashlib, uuid
repo=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser()
parser.add_argument('--build',default='build/windows-release-1.0.0/runner/Release')
parser.add_argument('--crt',default=r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT')
args=parser.parse_args()
root=repo/'release/1.0.0';name='PvZ-Formation-Editor-1.0.0-windows-x64'
root.mkdir(parents=True,exist_ok=True)
stage=repo/'build'/('pvz-release-stage-'+uuid.uuid4().hex[:12]);stage.mkdir();dst=stage/name
source=repo/args.build
for required in ['pvz_formation_editor.exe','flutter_windows.dll','data/app.so']:
    assert (source/required).is_file(),required
assert Path(args.crt).is_dir(),'MSVC app-local runtime directory missing'
shutil.copytree(source,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.pdb','*.lib','*.exp','*.ilk'))
for dll in Path(args.crt).glob('*.dll'):shutil.copy2(dll,dst/dll.name)
for required in ['vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll']:assert (dst/required).is_file(),required
shutil.copy2(repo/'ACKNOWLEDGMENTS.md',dst/'ACKNOWLEDGMENTS.md')
shutil.copy2(repo/'LICENSE',dst/'LICENSE')
shutil.copy2(repo/'docs/release-readme.txt',dst/'README.txt')
archive=root/(name+'.zip')
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as out:
    for file in sorted(dst.rglob('*')):
        if file.is_file():out.write(file,file.relative_to(stage))
with zipfile.ZipFile(archive) as out:assert out.testzip() is None
sha=hashlib.sha256(archive.read_bytes()).hexdigest()
(root/'SHA256SUMS.txt').write_text(f'{sha}  {archive.name}\n',encoding='ascii')
print(f'{archive}: {archive.stat().st_size} bytes; SHA256 {sha}')

(repo/'build/checks/latest-release-path.txt').write_text(str(dst/'pvz_formation_editor.exe'),encoding='utf-8')
