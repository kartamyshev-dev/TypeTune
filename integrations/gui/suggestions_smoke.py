#!/usr/bin/python3
import sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'ibus'))
from suggestion_editor import SuggestionEditor,Gtk,GLib
from gi.repository import Gio
app=Gtk.Application(application_id='dev.kartamyshev.TypeTune.SuggestionsStand',flags=Gio.ApplicationFlags.NON_UNIQUE)
app.register(None);parent=Gtk.ApplicationWindow(application=app)
proposals=[dict(id='one',source='ghbdtn',word='привет',backend='compatibility'),dict(id='two',source='rfr',word='как',backend='compatibility')]
resolved=[]
def exchange(command,value):
    if command=='suggestions-get':return dict(proposals=list(proposals))
    resolved.append(value)
    proposals[:]=[p for p in proposals if p['id']!=value['id']]
    return dict(error=False,message='Добавлено в «Слова и исключения».' if value['action']=='accept' else 'Отклонено')
editor=SuggestionEditor(parent,exchange)
ctx=GLib.MainContext.default()
def settle():
    deadline=time.monotonic()+3
    while editor.busy and time.monotonic()<deadline:ctx.iteration(True)
    assert not editor.busy
    while ctx.pending():ctx.iteration(False)
settle()
assert not editor.get_visible() and not resolved # Loading never presents or resolves.
editor.present();assert len(editor.rows)==2
if len(sys.argv)>1:
    from gi.repository import Graphene
    ready=[];GLib.timeout_add(200,lambda:ready.append(True) and False)
    while not ready:ctx.iteration(True)
    snapshot=Gtk.Snapshot.new();Gtk.WidgetPaintable.new(editor).snapshot(snapshot,editor.get_width(),editor.get_height())
    texture=editor.get_native().get_renderer().render_texture(snapshot.to_node(),Graphene.Rect().init(0,0,editor.get_width(),editor.get_height()))
    assert texture.save_to_png(sys.argv[1])
editor.rows[0].get_first_child().emit('clicked');settle()
assert resolved==[dict(id='one',backend='compatibility',action='accept')]
editor.rows[0].get_last_child().emit('clicked');settle()
assert resolved[-1]==dict(id='two',backend='compatibility',action='dismiss') and not editor.rows
editor.close();parent.close()
print('FEEDBACK-50-GTK: no implicit present/accept, explicit add/reject, empty state PASS')
