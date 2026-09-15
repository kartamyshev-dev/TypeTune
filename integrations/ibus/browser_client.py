#!/usr/bin/env python3
"""Local browser page as an independent readback oracle, no browser extension."""
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

base = Path(os.environ['TYPETUNE_NESTED_STAND']).resolve()
assert Path(os.environ['XDG_RUNTIME_DIR']).resolve() == base / 'runtime'
assert os.environ['WAYLAND_DISPLAY'] == 'typetune-test'
profile = sys.argv[1]
assert profile in ('default', 'ime', 'smart')
folder = base / ('browser-' + profile)
folder.mkdir()
(folder / 'phase').write_text('typing')
PAGE = br'''<!doctype html><meta charset="utf-8"><title>TypeTune browser fixture</title>
<style>textarea,input{position:absolute;left:20px;width:360px;height:70px}#a{top:20px}#b{top:140px}#p{top:260px}</style>
<textarea id="a" autofocus></textarea><textarea id="b"></textarea>
<input id="p" type="password" autocomplete="off">
<script>
const a=document.querySelector('#a'), b=document.querySelector('#b'), p=document.querySelector('#p');
let phase='typing', busy=false, pointer=null;
window.addEventListener('pointermove',e=>{pointer={x:e.clientX,y:e.clientY};});
function state() {
 return {phase, active:document.activeElement.id, focused:document.hasFocus(),
         text_ok:a.value==='ghbdtn', corrected:a.value==='\u043f\u0440\u0438\u0432\u0435\u0442', caret:a.selectionStart, anchor:a.selectionEnd,
         smart_ru:a.value==='\u043f\u0440\u0438\u0432\u0435\u0442', smart_us:a.value==='\u043f\u0440\u0438\u0432\u0435\u0442 hello',
         auto_ok:a.value==='\u043f\u0440\u0438\u0432\u0435\u0442 hello \u043f\u0440\u0438\u0432\u0435\u0442 ', next_ru:a.value==='\u043f\u0440\u0438\u0432\u0435\u0442 hello \u043f\u0440\u0438\u0432\u0435\u0442 \u043f',
         password_ok:p.value==='ghbdtn', second_empty:b.value==='', pointer,
         target_a:{x:a.getBoundingClientRect().right-15,y:a.getBoundingClientRect().top+20},
         target_b:{x:b.getBoundingClientRect().x+b.clientWidth/2,y:b.getBoundingClientRect().y+b.clientHeight/2}};
}
setInterval(async()=>{
 if(busy) return; busy=true;
 try {
  const next=await (await fetch('/phase',{cache:'no-store'})).text();
  if(next!==phase) {
   phase=next;
   if(next==='password') p.focus();
  }
  await fetch('/state',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(state())});
 } finally {busy=false;}
},50);
a.focus();
</script>'''


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == '/phase':
            data = (folder / 'phase').read_bytes()
            content = 'text/plain'
        elif self.path == '/':
            data, content = PAGE, 'text/html; charset=utf-8'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        size = int(self.headers.get('Content-Length', 0))
        if self.path != '/state' or not 0 < size < 1024:
            self.send_error(400)
            return
        value = json.loads(self.rfile.read(size))
        # Only our small synthetic state schema is ever written, never text.
        if set(value) != {'phase', 'active', 'focused', 'smart_ru', 'smart_us', 'auto_ok', 'next_ru', 'text_ok', 'corrected', 'caret', 'anchor', 'password_ok', 'second_empty', 'pointer', 'target_a', 'target_b'}:
            self.send_error(400)
            return
        temp = folder / 'state.tmp'
        temp.write_text(json.dumps(value))
        temp.replace(folder / 'state.json')
        self.send_response(204)
        self.end_headers()


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
args = ['google-chrome', '--ozone-platform=wayland', '--gtk-version=3', '--user-data-dir=' + str(folder / 'profile'),
        '--start-fullscreen', '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
        '--disable-component-update', '--disable-sync', '--disable-default-apps',
        '--password-store=basic', 'http://127.0.0.1:' + str(server.server_port)]
if profile == 'ime':
    args += ['--enable-wayland-ime', '--wayland-text-input-version=3']
browser_log = open(folder / 'browser.log', 'w+')
app = subprocess.Popen(args, stdout=browser_log, stderr=browser_log)
try:
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline and not (folder / 'finish').exists():
        if app.poll() is not None:
            browser_log.seek(0)
            print(browser_log.read(4000), flush=True)
            raise RuntimeError('browser exited: ' + str(app.returncode))
        time.sleep(.05)
    assert (folder / 'finish').exists(), 'browser fixture timeout'
finally:
    app.terminate()
    try:
        app.wait(timeout=3)
    except subprocess.TimeoutExpired:
        app.kill()
        app.wait()
    server.shutdown()
    server.server_close()
    browser_log.close()
