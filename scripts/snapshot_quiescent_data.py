#!/usr/bin/env python3
"""Private data snapshot while all original app processes and DB handles are closed."""
import argparse,hashlib,json,os,pathlib,shutil,sqlite3,subprocess,uuid
root=pathlib.Path(__file__).resolve().parents[1]
home=pathlib.Path.home()
parser=argparse.ArgumentParser()
parser.add_argument('--output',default='research/evidence/quiescent-'+uuid.uuid4().hex+'.json')
output=(root/parser.parse_args().output).resolve()
assert output.is_relative_to(root/'research/evidence') and not output.exists(),'Choose a new evidence filename inside research/evidence'
roots=[home/'Library/Containers/tech.caramba.switcher',home/'Library/Group Containers/AKZHD7272L.com.caramba-switcher.shared']
def original_stopped():
    rows=subprocess.check_output(['ps','-ww','-axo','comm='],text=True).splitlines()
    return not any('Caramba Switcher Pro.app/' in row or pathlib.Path(row).name=='Caramba Switcher Pro' for row in rows)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
assert original_stopped(),'Original process must be stopped'
files=[p for directory in roots if directory.exists() for p in directory.rglob('*') if p.is_file() and not p.is_symlink() and p.suffix in {'.redb','.sqlite','.plist'}]
redb=[p for p in files if p.suffix=='.redb'];assert redb,'No redb source found'
for path in files:
    if path.suffix not in {'.redb','.sqlite'}: continue
    handles=subprocess.run(['/usr/sbin/lsof','-n','-F','pfa',str(path)],capture_output=True,text=True)
    assert handles.returncode==1 and not handles.stdout and not handles.stderr,'DB is open or handle inventory failed'
before={str(p):digest(p) for p in files}
folder=root/'research/private'/('quiescent-'+uuid.uuid4().hex)
folder.mkdir(mode=0o700,parents=True,exist_ok=False)
private=[]
for path in files:
    idx=next(i for i,d in enumerate(roots) if path.is_relative_to(d))
    target=folder/str(idx)/path.relative_to(roots[idx]);target.parent.mkdir(parents=True,exist_ok=True)
    if path.suffix=='.sqlite':
        with sqlite3.connect(path.as_uri()+'?mode=ro',uri=True) as source,sqlite3.connect(target) as destination:
            source.backup(destination)
            assert destination.execute('PRAGMA integrity_check').fetchone()[0]=='ok','SQLite snapshot integrity failed'
    else:
        shutil.copy2(path,target)
        assert digest(target)==before[str(path)],'Copied bytes differ'
    os.chmod(target,0o600)
    private.append({'source':str(path),'copy':str(target.relative_to(folder)),'sourceSha256':before[str(path)],'copySha256':digest(target)})
assert original_stopped(),'Original started during snapshot'
assert before=={str(p):digest(p) for p in files},'Source changed during snapshot'
(folder/'manifest.json').write_text(json.dumps(private,indent=2)+'\n');os.chmod(folder/'manifest.json',0o600)
report={'originalStoppedBeforeAndAfter':True,'dbHandlesClosedBeforeCopy':True,'sourceBytesStable':True,'redbCopiesByteEqual':len(redb),'sqliteBackupsVerified':sum(p.suffix=='.sqlite' for p in files),'settingsCopies':sum(p.suffix=='.plist' for p in files),'privateDestination':str(folder.relative_to(root)),'personalDataPublished':False,'redbFormatIntegrityVerified':False,'notice':'Quiescent byte-consistent redb backup; no semantic redb-format validation. SQLite backup API includes WAL. Source DB/settings never written.'}
output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='privateDestination'}))
