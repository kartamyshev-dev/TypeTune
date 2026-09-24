#!/usr/bin/python3
"""Build the current GNOME preview, not the historical daemon package."""
import argparse,ast,json,os,re,shutil,subprocess,tempfile
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]

def run(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
def build(version,output):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+~:-]*',version):raise ValueError('Invalid Debian version')
    arch=subprocess.check_output(['dpkg','--print-architecture'],text=True).strip()
    for args in [('typetune-bridge',),('typetune-cli','--example','compat_transport'),('typetune-cli',),('typetune-gui',)]:
        run(['cargo','build','-p',*args,'--release','--locked','--offline'],cwd=REPO)
    output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='typetune-deb-') as temporary:
        base=Path(temporary);root=base/'root';payload=root/'usr/lib/typetune-preview';payload.mkdir(parents=True)
        def copy(source,target,mode=0o644):
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target);target.chmod(mode)
        tree=ast.parse((REPO/'integrations/app/controller.py').read_text())
        files=next(ast.literal_eval(node.value) for node in tree.body if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='FILES' for t in node.targets))
        for name in (*files,'package_launcher.py','layout-switch.wav'):copy(REPO/'integrations/app'/name,payload/name)
        for source in (REPO/'integrations/compat').glob('*.py'):
            if not source.name.startswith('test_'):copy(source,payload/'compat'/source.name)
        copy(REPO/'target/release/libtypetune_bridge.so',payload/'libtypetune_bridge.so')
        copy(REPO/'target/release/examples/compat_transport',payload/'compat/compat_transport',0o755)
        # Native shell (0.2.0): optional GTK window + CLI doctor; Python tray remains default.
        copy(REPO/'target/release/typetune-gui',root/'usr/bin/typetune-gui',0o755)
        copy(REPO/'target/release/typetune',root/'usr/bin/typetune',0o755)
        shutil.copytree(REPO/'integrations/gnome',payload/'gnome',ignore=shutil.ignore_patterns('__pycache__'))
        (payload/'package.json').write_text(json.dumps(dict(version=version,architecture=arch,profile='gnome50',source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),source_dirty=bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=REPO,text=True).strip())))+'\n')
        for name in ('manage-access','session-lifecycle'):copy(REPO/'packaging/preview'/name,payload/name,0o755)
        launcher=root/'usr/bin/typetune-preview';launcher.parent.mkdir(parents=True,exist_ok=True)
        launcher.write_text('#!/bin/sh\nexec /usr/bin/python3 /usr/lib/typetune-preview/package_launcher.py "$@"\n');launcher.chmod(0o755)
        copy(REPO/'packaging/preview/typetune-preview.desktop',root/'usr/share/applications/dev.kartamyshev.TypeTune.Preview.desktop')
        copy(REPO/'packaging/preview/typetune-setup.desktop',root/'usr/share/applications/dev.kartamyshev.TypeTune.Setup.desktop')
        for icon in (REPO/'resources/icons/hicolor/scalable/status').glob('*.svg'):
            copy(icon,root/'usr/share/icons/hicolor/scalable/status'/icon.name)
        copy(REPO/'packaging/preview/org.typetune.preview.manage.policy',root/'usr/share/polkit-1/actions/org.typetune.preview.manage.policy')
        rule=root/'usr/lib/udev/rules.d/70-typetune-preview.rules';rule.parent.mkdir(parents=True)
        rule.write_text('KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660"\n')
        module=root/'usr/lib/modules-load.d/typetune-preview.conf';module.parent.mkdir(parents=True);module.write_text('uinput\n')
        docs=root/'usr/share/doc/typetune-preview';docs.mkdir(parents=True)
        copy(REPO/'LICENSE',docs/'copyright')
        copy(REPO/'docs/user-guide.md',docs/'README.md')
        for name in ('install.md','troubleshooting.md','security-privacy.md'):
            copy(REPO/'docs'/name,docs/name)
        shutil.copytree(REPO/'crates/typetune-engine/data/frequency',docs/'frequencywords',ignore=shutil.ignore_patterns('*.txt','*.tsv'))
        # The frequency data is compiled into the library; retain upstream licence too.
        for source in (REPO/'crates/typetune-engine/data/frequency').rglob('*'):
            if source.is_file() and ('license' in source.name.lower() or 'copying' in source.name.lower()):copy(source,docs/'frequencywords'/source.relative_to(REPO/'crates/typetune-engine/data/frequency'))
        # Include upstream licence notices for the resolved Cargo graph (a superset
        # of the two shipped targets); no network access during packaging.
        host=next(line.split(': ',1)[1] for line in subprocess.check_output(['rustc','-vV'],text=True).splitlines() if line.startswith('host: '))
        cargo=json.loads(subprocess.check_output(['cargo','metadata','--locked','--offline','--format-version=1','--filter-platform',host],cwd=REPO,text=True))
        notices=docs/'rust-licenses';notices.mkdir()
        index=[]
        for crate in cargo['packages']:
            if not crate.get('source'):continue
            directory=Path(crate['manifest_path']).parent
            candidates=[p for p in directory.iterdir() if p.is_file() and p.name.upper().startswith(('LICENSE','LICENCE','COPYING','NOTICE','COPYRIGHT'))]
            if crate.get('license_file'):candidates.append(directory/crate['license_file'])
            destination=notices/(crate['name']+'-'+crate['version'])
            for source in set(candidates):
                if source.is_file():copy(source,destination/source.name)
            index.append(dict(name=crate['name'],version=crate['version'],license=crate['license'],authors=crate['authors'],repository=crate['repository']))
        (notices/'manifest.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n')
        debian=base/'debian';debian.mkdir();(debian/'control').write_text('Source: typetune-preview\n\nPackage: typetune-preview\nArchitecture: any\nDescription: TypeTune preview\n')
        dependencies=subprocess.check_output(['dpkg-shlibdeps','-O','-e'+str(payload/'libtypetune_bridge.so'),'-e'+str(payload/'compat/compat_transport'),'-e'+str(root/'usr/bin/typetune-gui'),'-e'+str(root/'usr/bin/typetune')],cwd=base,text=True).strip().split('=',1)[1]
        metadata=root/'DEBIAN';metadata.mkdir()
        installed_size=sum(p.stat().st_size for p in root.rglob('*') if p.is_file())//1024
        (metadata/'control').write_text(f'''Package: typetune-preview
Version: {version}
Architecture: {arch}
Maintainer: TypeTune contributors <noreply@typetune.local>
Section: utils
Priority: optional
Installed-Size: {installed_size}
Depends: {dependencies}, python3, python3-gi, gir1.2-gtk-4.0, gnome-shell (>= 50), gnome-shell (<< 51), dconf-gsettings-backend, pkexec, policykit-1 | polkitd, passwd, kmod, udev
Recommends: gnome-shell-ubuntu-extensions | gnome-shell-extension-appindicator
Description: RU/EN layout correction preview for GNOME 50
 Prebuilt user-session application with Double Shift, automatic correction,
 a graphical setup and settings. Input-device access is an explicit user action.
 User dictionaries and preferences survive upgrades and package removal.
''')
        for name in ('prerm','postinst','postrm'):copy(REPO/'packaging/preview'/name,metadata/name,0o755)
        for path in root.rglob('*'):
            path.chmod(0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
        # Normalize ownership through dpkg; no privileged build steps.
        artifact=output/f'typetune-preview_{version}_{arch}.deb'
        run(['dpkg-deb','--root-owner-group','--build',str(root),str(artifact)])
        return artifact
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--version',default='0.1.0~preview58-2');parser.add_argument('--output',type=Path,default=REPO/'dist')
    args=parser.parse_args();print(build(args.version,args.output))
