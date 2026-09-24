#!/usr/bin/python3
"""Real GTK package setup UI, controlled operations; never invokes privileges."""
import sys,time,subprocess
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
import package_launcher as setup
from gi.repository import Gio,GLib
Gtk=setup.Gtk
app=Gtk.Application(application_id='dev.kartamyshev.TypeTune.PackageStand',flags=Gio.ApplicationFlags.NON_UNIQUE);app.register(None)
configured=[False];commands=[]
def runner(args,**kwargs):
    commands.append(args)
    if args[-1]=='package-configure':configured[0]=True;return subprocess.CompletedProcess(args,0,'','')
    return subprocess.CompletedProcess(args,126,'','') # System authentication cancelled.
ctx=GLib.MainContext.default()
with patch.object(setup,'configured',side_effect=lambda:configured[0]):
    window=setup.Setup(app,runner);window.present()
    def settle():
        deadline=time.monotonic()+3
        while window.busy and time.monotonic()<deadline:ctx.iteration(True)
        assert not window.busy
        while ctx.pending():ctx.iteration(False)
    assert not window.open.get_sensitive() and not commands
    window.configure.emit('clicked');settle();assert window.open.get_sensitive()
    # This fixture isn't installed, so directly invoke the button's handler.
    window.run('permissions');settle()
    assert commands[-1]==['/usr/bin/pkexec','/usr/lib/typetune-preview/manage-access','input-access']
    assert 'отменён' in window.message.get_label()
    assert window.open.get_sensitive()
    window.run('remove');settle();assert commands[-1][-1]=='remove'
    if len(sys.argv)>1:
        from gi.repository import Graphene
        ready=[];GLib.timeout_add(200,lambda:ready.append(True) and False)
        while not ready:ctx.iteration(True)
        snapshot=Gtk.Snapshot.new();Gtk.WidgetPaintable.new(window).snapshot(snapshot,window.get_width(),window.get_height())
        texture=window.get_native().get_renderer().render_texture(snapshot.to_node(),Graphene.Rect().init(0,0,window.get_width(),window.get_height()))
        assert texture.save_to_png(sys.argv[1])
    window.close()
# Native shell doctor: exit code + stable macOS-parity keys (binary from cargo).
doctor=Path(__file__).resolve().parents[2]/'target/debug/typetune'
if doctor.is_file():
    result=subprocess.run([str(doctor),'doctor','--session'],
                          capture_output=True,text=True,timeout=20,
                          env={**__import__('os').environ,'DBUS_SESSION_BUS_ADDRESS':'unix:path=/nonexistent/typetune-doctor/bus'})
    assert result.returncode==0, result.stderr
    import json
    report=json.loads(result.stdout)
    for key in ('protocol','os','input_source','autostart','permissions','schema_version'):
        assert key in report, key
    print('PKG-51-DOCTOR: typetune doctor --session keys PASS')
print('PKG-51-GTK: no implicit permission grant, configure/open, cancelled access/removal PASS')
