"""User vocabulary editor; persistence/effective apply belong to controller."""
import json
import subprocess
import threading
from pathlib import Path
import gi
gi.require_version('Gtk','4.0')
from gi.repository import Gtk, GLib


def exchange(command, document=None):
    result = subprocess.run(['/usr/bin/python3', str(Path(__file__).with_name('controller.py')), command],
                            input=json.dumps(document,ensure_ascii=False) if document else None,
                            capture_output=True,text=True,timeout=20,check=False)
    if result.returncode: raise RuntimeError(result.stderr.strip() or 'Не удалось выполнить команду настройки')
    return json.loads(result.stdout)


class WordEditor(Gtk.Window):
    def __init__(self, parent, requester=exchange):
        super().__init__(title='Слова и исключения', transient_for=parent, modal=True, default_width=600, default_height=660)
        self.parent_window=parent; self.requester=requester
        self.document=None; self.busy=False; self.closed=False
        self.set_titlebar(Gtk.HeaderBar())
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12,margin_top=20,margin_bottom=20,margin_start=24,margin_end=24)
        scroll=Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER);scroll.set_child(box);self.set_child(scroll)
        self.views={}
        for key,title,help_text in [
            ('words','Мои слова','Правильные слова RU или EN: распознавать при автокоррекции и не менять, если они уже набраны верно.'),
            ('exclusions','Не исправлять','Не выполнять автозамену, если исходное слово или результат есть в этом списке. Double Shift продолжает работать.')]:
            label=Gtk.Label(label=title,xalign=0);label.add_css_class('title-3');box.append(label)
            box.append(Gtk.Label(label=help_text,xalign=0,wrap=True))
            view=Gtk.TextView(wrap_mode=Gtk.WrapMode.NONE,top_margin=8,bottom_margin=8,left_margin=8,right_margin=8)
            self.views[key]=view
            area=Gtk.ScrolledWindow(min_content_height=125);area.set_child(view);area.set_has_frame(True);box.append(area)
        box.append(Gtk.Label(label='По одному слову на строку, 2–32 буквы. До 5000 слов в каждом списке. Регистр не учитывается; исключения имеют приоритет.',wrap=True,xalign=0))
        self.message=Gtk.Label(label='Загрузка…',wrap=True,xalign=0);box.append(self.message)
        self.save=Gtk.Button(label='Сохранить и применить');self.save.add_css_class('suggested-action');box.append(self.save)
        self.save.connect('clicked',self.save_clicked)
        self.connect('close-request',self.closing)
        self.run('words-get')

    def closing(self,*_):
        if self.busy: return True
        self.closed=True; self.parent_window.word_editor=None
        return False

    def save_clicked(self,*_):
        if self.document is None or self.busy:return
        value=dict(self.document)
        for key,view in self.views.items():
            buffer=view.get_buffer()
            value[key]=[line.strip() for line in buffer.get_text(buffer.get_start_iter(),buffer.get_end_iter(),False).splitlines() if line.strip()]
        self.run('words-save',value)

    def run(self,command,value=None):
        if self.busy:return
        self.busy=True;self.save.set_sensitive(False)
        for view in self.views.values():view.set_editable(False)
        self.message.set_label('Сохранение…' if value else 'Загрузка…')
        def work():
            try:result=self.requester(command,value);error=None
            except Exception as exc:result=None;error=str(exc)
            GLib.idle_add(self.complete,command,result,error)
        threading.Thread(target=work,daemon=True).start()

    def complete(self,command,result,error):
        if self.closed:return False
        if error:
            self.message.set_label(error)
        else:
            self.document=result if command=='words-get' else result['document']
            for key,view in self.views.items():view.get_buffer().set_text('\n'.join(self.document[key]))
            self.message.set_label('Измените списки и нажмите «Сохранить и применить».' if command=='words-get' else result['message'])
        self.busy=False
        for view in self.views.values():view.set_editable(self.document is not None)
        self.save.set_sensitive(self.document is not None)
        return False
