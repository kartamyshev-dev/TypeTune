import pathlib,hashlib,json
root=pathlib.Path('/Applications/Caramba Switcher Pro.app')
expected=json.loads(pathlib.Path('research/evidence/original-manifest.json').read_text())
for row in expected:
 p=root/row['path']
 if 'sha256' in row: assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'], row['path']
 else: assert str(p.readlink())==row['symlink']
pathlib.Path('research/evidence/unchanged-original.json').write_text(json.dumps({'matchedEntries':len(expected),'allMatched':True,'scope':'installed bundle only; runtime statistics may change during tests'},indent=2)+'\n')
print('Installed original unchanged:',len(expected),'entries')
