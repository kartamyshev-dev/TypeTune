#!/usr/bin/python3
"""Real dpkg install/upgrade/remove/purge in an isolated user-namespace root."""
import json,os,shutil,subprocess,sys,tempfile
from pathlib import Path
artifact=Path(sys.argv[1]).resolve()
def run(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
with tempfile.TemporaryDirectory(prefix='typetune-dpkg-') as temporary:
    base=Path(temporary);root=base/'root';root.mkdir()
    dpkg=([] if os.geteuid()==0 else ['unshare','-Ur'])+['dpkg','--root='+str(root),'--force-script-chrootless','--force-depends']
    user=root/'home/fixture/.config/typetune';user.mkdir(parents=True)
    for name in ('settings.json','words.json','applications.json'):(user/name).write_text('fixture-preserved\n')
    original={p.name:p.read_bytes() for p in user.iterdir()}
    if len(sys.argv)>2:
        run([*dpkg,'--install',str(Path(sys.argv[2]).resolve())])
    run([*dpkg,'--install',str(artifact)])
    payload=root/'usr/lib/typetune-preview'
    assert (payload/'libtypetune_bridge.so').is_file()
    for legacy in ('libtypetune_ibus.so','runtime_engine.py','probe_engine.py','manual.py','session_guard.py','editor_guard.py'):
        assert not (payload/legacy).exists(), legacy
    depends=subprocess.check_output(['dpkg-deb','-f',str(artifact),'Depends'],text=True)
    assert 'ibus' not in depends and 'gir1.2-atspi' not in depends
    assert (payload/'compat/compat_transport').stat().st_mode & 0o111
    assert not (root/'usr/lib/systemd/system/typetune.service').exists()
    assert not list(root.rglob('*.pyc'))
    desktop=root/'usr/share/applications/dev.kartamyshev.TypeTune.Preview.desktop'
    run(['desktop-file-validate',str(desktop)])
    control=base/'repack';run(['dpkg-deb','-R',str(artifact),str(control)],stdout=subprocess.DEVNULL)
    path=control/'DEBIAN/control';text=path.read_text();old=next(line.split(': ',1)[1] for line in text.splitlines() if line.startswith('Version:'))
    version=old+'+test1';path.write_text(text.replace('Version: '+old,'Version: '+version))
    package=control/'usr/lib/typetune-preview/package.json';metadata=json.loads(package.read_text());metadata['version']=version;package.write_text(json.dumps(metadata))
    updated=base/'update.deb';run(['dpkg-deb','--root-owner-group','--build',str(control),str(updated)],stdout=subprocess.DEVNULL)
    run([*dpkg,'--install',str(updated)])
    assert json.loads((payload/'package.json').read_text())['version']==version
    assert {p.name:p.read_bytes() for p in user.iterdir()}==original
    run([*dpkg,'--remove','typetune-preview'])
    assert not payload.exists() and not desktop.exists()
    assert {p.name:p.read_bytes() for p in user.iterdir()}==original
    run([*dpkg,'--purge','typetune-preview'])
    run([*dpkg,'--install',str(artifact)])
    assert {p.name:p.read_bytes() for p in user.iterdir()}==original
    print('PKG-51-DPKG: install/upgrade/remove/purge/reinstall, user files preserved PASS')
