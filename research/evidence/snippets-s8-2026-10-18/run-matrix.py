import json,pathlib,subprocess,sys
p=pathlib.Path(__file__).parent;e=pathlib.Path("research/evidence/snippets-s8-2026-10-18")
name,bundle,window,description=sys.argv[1:];description=None if description=="null" else description
cases=[("thanks","cgc ","RussianWin","спасибо ",None)]+json.loads((p/"cases.json").read_text())
for ident,text,source,expected,caret in cases:
 d=dict(bundle=bundle,window=window,description=description,text=text,expected=expected,source="com.apple.keylayout."+source,expectedSource="com.apple.keylayout."+source,gesture="none",clearAfter=True)
 if caret is not None:d["expectedCaret"]=caret
 f=p/(name+"-"+ident+"-case.json");f.write_text(json.dumps(d,ensure_ascii=False));r=subprocess.run([str(p/"matrix-probe"),str(f)],capture_output=True,text=True);(e/(name+"-"+ident+".json")).write_text(r.stdout);print(ident,r.returncode,flush=True)
 if r.returncode:break
