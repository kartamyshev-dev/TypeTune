"""Explicit review only. Never presents a window or steals focus on a new proposal."""
import threading
import gi
gi.require_version('Gtk','4.0')
from gi.repository import Gtk, GLib
from word_editor import exchange

class SuggestionEditor(Gtk.Window):
    def __init__(self,parent,requester=exchange):
        super().__init__(title='Предложения для словаря',transient_for=parent,modal=False,default_width=570,default_height=480)
        self.parent_window=parent;self.requester=requester;self.busy=False;self.closed=False;self.rows=[]
        self.set_titlebar(Gtk.HeaderBar())
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14,margin_top=20,margin_bottom=20,margin_start=24,margin_end=24)
        self.set_child(box)
        box.append(Gtk.Label(label='После трёх возвратов автозамены предлагается исключение. После трёх отдельных ручных исправлений — слово для автокоррекции. Пробел можно нажать до или после Double Shift. Ничего не добавляется без вашего подтверждения.',wrap=True,xalign=0))
        self.list=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=18)
        scroll=Gtk.ScrolledWindow(vexpand=True,hscrollbar_policy=Gtk.PolicyType.NEVER);scroll.set_child(self.list);box.append(scroll)
        self.message=Gtk.Label(wrap=True,xalign=0);box.append(self.message)
        box.append(Gtk.Label(label='Добавленное слово можно удалить в «Слова и исключения». Отклонённое предложение не повторяется до перезапуска TypeTune.',wrap=True,xalign=0))
        self.refresh=Gtk.Button(label='Обновить список');self.refresh.connect('clicked',lambda *_:self.run());box.append(self.refresh)
        self.connect('close-request',self.closing);self.run()
    def closing(self,*_):
        if self.busy:return True
        self.closed=True;self.parent_window.suggestion_editor=None;return False
    def run(self,value=None):
        if self.busy:return
        self.busy=True;self.list.set_sensitive(False);self.refresh.set_sensitive(False)
        def worker():
            try:
                result=self.requester('suggestions-resolve',value) if value else None
                data=self.requester('suggestions-get',None)
                message=result['message'] if result else ''
            except Exception as exc:data=None;message=str(exc)
            GLib.idle_add(self.complete,data,message)
        threading.Thread(target=worker,daemon=True).start()
    def complete(self,data,message):
        if self.closed:return False
        if data is not None:
            child=self.list.get_first_child()
            while child:
                self.list.remove(child);child=self.list.get_first_child()
            self.rows=[]
            if not data['proposals']:
                self.list.append(Gtk.Label(label='Пока нет предложений. Одного ручного переключения недостаточно.',wrap=True,xalign=0))
            for proposal in data['proposals']:
                row=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=8)
                verb='Исправлять' if proposal.get('kind')=='word' else 'Не исправлять'
                row.append(Gtk.Label(label=f'{verb} «{proposal["source"]}» → «{proposal["word"]}» автоматически?',wrap=True,xalign=0))
                buttons=Gtk.Box(spacing=10)
                for action,label in [('accept','Добавить'),('dismiss','Отклонить')]:
                    button=Gtk.Button(label=label)
                    payload=dict(id=proposal['id'],backend=proposal['backend'],action=action)
                    button.connect('clicked',lambda _,p=payload:self.run(p))
                    buttons.append(button)
                row.append(buttons);self.list.append(row);self.rows.append(buttons)
        self.message.set_label(message);self.busy=False;self.list.set_sensitive(True);self.refresh.set_sensitive(True)
        return False
