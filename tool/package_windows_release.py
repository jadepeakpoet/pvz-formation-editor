"""Create the complete Windows x64 ZIP, including app-local MSVC runtimes."""
from pathlib import Path
import argparse, shutil, zipfile, hashlib, uuid, re, subprocess, os
repo=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser()
parser.add_argument('--version',default=re.search(r'^version: (\d+\.\d+\.\d+)',(repo/'pubspec.yaml').read_text(encoding='utf-8'),re.M).group(1))
parser.add_argument('--build',required=True,help='The verified Windows Release directory to package')
parser.add_argument('--crt',help='MSVC x64 CRT directory; automatically discovered when omitted')
args=parser.parse_args()
assert re.fullmatch(r'\d+\.\d+\.\d+',args.version),'Invalid release version'
root=repo/'release'/args.version;name=f'PvZ-Formation-Editor-{args.version}-windows-x64'
root.mkdir(parents=True,exist_ok=True)
stage=repo/'build'/('pvz-release-stage-'+uuid.uuid4().hex[:12]);stage.mkdir();dst=stage/name
source=repo/args.build
for required in ['pvz_formation_editor.exe','flutter_windows.dll','data/app.so']:
    assert (source/required).is_file(),required
assert source.is_dir(),'Release directory missing'
if os.name=='nt':
    binary_version=subprocess.check_output(['powershell','-NoProfile','-Command',
        '(Get-Item -LiteralPath $env:PVZ_PACKAGE_EXE).VersionInfo.ProductVersion'],
        env=dict(os.environ,PVZ_PACKAGE_EXE=str((source/'pvz_formation_editor.exe').resolve())),
        text=True).strip()
    assert binary_version.split('+')[0]==args.version,'Binary version does not match package version'
if args.crt is None:
    candidates=[]
    for base in [Path(r'C:\Program Files\Microsoft Visual Studio'),Path(r'C:\Program Files (x86)\Microsoft Visual Studio')]:
        for edition in ['BuildTools','Community','Professional','Enterprise']:
            candidates.extend(base.glob('*/'+edition+'/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT'))
    candidates=[p for p in candidates if all((p/n).is_file() for n in ['vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll'])]
    assert candidates,'MSVC app-local runtime not found; specify --crt'
    args.crt=str(max(candidates,key=lambda p:tuple(int(x) for x in re.findall(r'\d+',p.parent.parent.name))))
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
(root/'SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n'
    for file in sorted(root.glob('*.zip'))),encoding='ascii')
print(f'{archive}: {archive.stat().st_size} bytes; SHA256 {sha}')

(repo/'build/checks/latest-release-path.txt').write_text(str(dst/'pvz_formation_editor.exe'),encoding='utf-8')
