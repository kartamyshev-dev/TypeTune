"""Desktop application picker. Controller owns persistence and runtime apply."""
import threading
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib
from word_editor import exchange


class ApplicationEditor(Gtk.Window):
    def __init__(self, parent, requester=exchange):
        super().__init__(title='Исключения приложений', transient_for=parent, modal=True,
                         default_width=620, default_height=620)
        self.parent_window=parent; self.requester=requester
        self.document=None; self.busy=False; self.closed=False; self.rows={}
        self.set_titlebar(Gtk.HeaderBar())
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                    margin_top=20, margin_bottom=20, margin_start=24, margin_end=24)
        self.set_child(box)
        help_text=('Отметьте приложения, где автокоррекция после пробела должна быть выключена. '
                   'Double Shift продолжит переключать последнее слово и раскладку.')
        box.append(Gtk.Label(label=help_text, wrap=True, xalign=0))
        self.search=Gtk.SearchEntry(placeholder_text='Найти приложение')
        self.search.connect('search-changed',self.filter_rows);box.append(self.search)
        self.list=Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
        scroll=Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.set_has_frame(True);scroll.set_child(self.list);box.append(scroll)
        self.count=Gtk.Label(xalign=0);box.append(self.count)
        box.append(Gtk.Label(label='Исключение действует на все окна выбранного приложения. '
            'Если приложение не определено и список не пуст, автокоррекция не выполняется.',wrap=True,xalign=0))
        self.message=Gtk.Label(label='Загрузка…',wrap=True,xalign=0);box.append(self.message)
        self.save=Gtk.Button(label='Сохранить и применить');self.save.add_css_class('suggested-action')
        self.save.connect('clicked',self.save_clicked);box.append(self.save)
        self.connect('close-request',self.closing)
        self.run('apps-get')

    def closing(self,*_):
        if self.busy:return True
        self.closed=True;self.parent_window.application_editor=None
        return False

    def populate(self, catalog):
        entries={item['id']:item['name'] for item in catalog}
        for identifier in self.document['excluded']:
            entries.setdefault(identifier, identifier+' — не найдено в установленных')
        for identifier,name in sorted(entries.items(),key=lambda item:(item[1].casefold(),item[0])):
            row=Gtk.ListBoxRow()
            content=Gtk.Box(spacing=10,margin_top=8,margin_bottom=8,margin_start=10,margin_end=10)
            check=Gtk.CheckButton(valign=Gtk.Align.CENTER)
            check.set_active(identifier in self.document['excluded'])
            check.update_property([Gtk.AccessibleProperty.LABEL],[name])
            check.connect('toggled',self.update_count)
            labels=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=3,hexpand=True)
            labels.append(Gtk.Label(label=name,xalign=0,wrap=True))
            sub=Gtk.Label(label=identifier,xalign=0,wrap=True);sub.add_css_class('dim-label');labels.append(sub)
            content.append(check);content.append(labels);row.set_child(content);self.list.append(row)
            self.rows[identifier]=(row,check,(name+' '+identifier).casefold())
        self.list.connect('row-activated',self.activate_row)
        self.update_count();self.filter_rows()

    def activate_row(self,_,row):
        if self.busy:return
        for candidate,check,_ in self.rows.values():
            if candidate==row:check.set_active(not check.get_active());break

    def update_count(self,*_):
        self.count.set_label(f'Исключено приложений: {sum(check.get_active() for _,check,_ in self.rows.values())}')

    def filter_rows(self,*_):
        query=self.search.get_text().strip().casefold()
        for row,_,text in self.rows.values():row.set_visible(query in text)

    def save_clicked(self,*_):
        if self.document is None or self.busy:return
        selected=[identifier for identifier,(_,check,_) in self.rows.items() if check.get_active()]
        self.run('apps-save',dict(self.document,excluded=selected))

    def run(self,command,value=None):
        if self.busy:return
        self.busy=True;self.save.set_sensitive(False);self.list.set_sensitive(False)
        self.message.set_label('Сохранение…' if value else 'Загрузка…')
        def work():
            try:result=self.requester(command,value);error=None
            except Exception as exc:result=None;error=str(exc)
            GLib.idle_add(self.complete,command,result,error)
        threading.Thread(target=work,daemon=True).start()

    def complete(self,command,result,error):
        if self.closed:return False
        if error:self.message.set_label(error)
        else:
            self.document=result['document']
            if command=='apps-get':self.populate(result['catalog'])
            self.message.set_label('Выберите приложения и сохраните изменения.' if command=='apps-get' else result['message'])
        self.busy=False;self.list.set_sensitive(self.document is not None)
        self.save.set_sensitive(self.document is not None)
        return False
