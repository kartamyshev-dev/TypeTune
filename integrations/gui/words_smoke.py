#!/usr/bin/python3
"""GTK vocabulary editor acceptance with isolated persistent storage."""
import sys,time,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'app'))
from gui import Gtk,Gio,GLib
from word_editor import WordEditor
import preferences

app=Gtk.Application(application_id='dev.kartamyshev.TypeTune.WordsStand',flags=Gio.ApplicationFlags.NON_UNIQUE)
app.register(None)
parent=Gtk.ApplicationWindow(application=app)
ctx=GLib.MainContext.default()
with tempfile.TemporaryDirectory() as directory:
    path=Path(directory)/'words.json'
    def exchange(command,document):
        if command=='words-get':return preferences.load(path)
        saved=preferences.save(document,document['generation'],path)
        return dict(document=saved,message='Сохранено. Применится при запуске коррекции',applied=False,error=False)
    editor=WordEditor(parent,exchange);parent.word_editor=editor;editor.present()
    def settle():
        deadline=time.monotonic()+3
        while editor.busy and time.monotonic()<deadline:ctx.iteration(True)
        assert not editor.busy
        while ctx.pending():ctx.iteration(False)
    settle()
    editor.views['words'].get_buffer().set_text('Клавиатуры\nКЛАВИАТУРЫ')
    editor.views['exclusions'].get_buffer().set_text('Привет')
    editor.save.emit('clicked');settle()
    assert preferences.load(path)['words']==['клавиатуры']
    assert preferences.load(path)['exclusions']==['привет']
    generation=editor.document['generation']
    editor.views['words'].get_buffer().set_text('bad word')
    editor.save.emit('clicked');settle()
    assert '2–32' in editor.message.get_label()
    assert preferences.load(path)['generation']==generation
    editor.views['words'].get_buffer().set_text('клавиатуры')
    # Another editor wins; stale content must not overwrite its changes.
    saved=preferences.save(dict(editor.document,words=['hello']),generation,path)
    editor.save.emit('clicked');settle()
    assert 'другим окном' in editor.message.get_label()
    assert preferences.load(path)==saved
    editor.close()
    assert parent.word_editor is None
    editor=WordEditor(parent,exchange);editor.present();settle()
    assert editor.document['words']==['hello']
    if len(sys.argv)>1:
        from gi.repository import Graphene
        ready=[];GLib.timeout_add(200,lambda:ready.append(True) and False)
        while not ready:ctx.iteration(True)
        snapshot=Gtk.Snapshot.new()
        Gtk.WidgetPaintable.new(editor).snapshot(snapshot,editor.get_width(),editor.get_height())
        texture=editor.get_native().get_renderer().render_texture(snapshot.to_node(),Graphene.Rect().init(0,0,editor.get_width(),editor.get_height()))
        assert texture.save_to_png(sys.argv[1])
    editor.close();parent.close()
print('WORDS-47 GTK editor: save/reopen/normalization/invalid/stale conflict PASS')
