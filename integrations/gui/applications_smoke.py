#!/usr/bin/python3
"""GTK application picker with isolated storage; no real input injection."""
import sys,time,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ibus'))
from gui import Gtk,Gio,GLib
from application_editor import ApplicationEditor
import application_rules as rules

app=Gtk.Application(application_id='dev.kartamyshev.TypeTune.ApplicationsStand',flags=Gio.ApplicationFlags.NON_UNIQUE)
app.register(None)
parent=Gtk.ApplicationWindow(application=app)
ctx=GLib.MainContext.default()
with tempfile.TemporaryDirectory() as directory:
    path=Path(directory)/'applications.json'
    catalog=[dict(id='code.desktop',name='Редактор кода'),dict(id='browser.desktop',name='Браузер'),dict(id='terminal.desktop',name='Терминал')]
    def exchange(command,document):
        if command=='apps-get':return dict(document=rules.load(path),catalog=catalog)
        saved=rules.save(document,document['generation'],path)
        return dict(document=saved,message='Сохранено. Применится при запуске коррекции',applied=False,error=False)
    editor=ApplicationEditor(parent,exchange);parent.application_editor=editor;editor.present()
    def settle():
        deadline=time.monotonic()+3
        while editor.busy and time.monotonic()<deadline:ctx.iteration(True)
        assert not editor.busy
        while ctx.pending():ctx.iteration(False)
    settle()
    editor.rows['code.desktop'][1].set_active(True)
    editor.search.set_text('терминал');editor.filter_rows()
    assert editor.rows['terminal.desktop'][0].get_visible()
    assert not editor.rows['code.desktop'][0].get_visible()
    editor.rows['terminal.desktop'][1].set_active(True)
    editor.save.emit('clicked');settle()
    assert rules.load(path)['excluded']==['code.desktop','terminal.desktop'] # Filtering keeps hidden selections.
    saved=rules.save(dict(editor.document,excluded=['removed.desktop']),editor.document['generation'],path)
    editor.save.emit('clicked');settle()
    assert 'другим окном' in editor.message.get_label()
    assert rules.load(path)==saved
    assert editor.rows['code.desktop'][1].get_active() # Preserve stale draft, never pretend it was saved.
    editor.close();assert parent.application_editor is None
    editor=ApplicationEditor(parent,exchange);editor.present();settle()
    assert editor.rows['removed.desktop'][1].get_active() # Uninstalled app remains removable.
    editor.rows['removed.desktop'][1].set_active(False)
    editor.rows['terminal.desktop'][1].set_active(True)
    editor.save.emit('clicked');settle()
    assert rules.load(path)['excluded']==['terminal.desktop']
    if len(sys.argv)>1:
        from gi.repository import Graphene
        ready=[];GLib.timeout_add(200,lambda:ready.append(True) and False)
        while not ready:ctx.iteration(True)
        snapshot=Gtk.Snapshot.new()
        Gtk.WidgetPaintable.new(editor).snapshot(snapshot,editor.get_width(),editor.get_height())
        texture=editor.get_native().get_renderer().render_texture(snapshot.to_node(),Graphene.Rect().init(0,0,editor.get_width(),editor.get_height()))
        assert texture.save_to_png(sys.argv[1])
    editor.close();parent.close()
print('APPS-49-GTK search/hidden selections/save/reopen/stale conflict/remove missing app PASS')
