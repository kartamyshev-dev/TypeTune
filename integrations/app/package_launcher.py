#!/usr/bin/python3
"""Graphical per-user setup for the prebuilt Debian package. Never run GTK as root."""
import json
import os
from pathlib import Path
import subprocess
import threading
import gi
gi.require_version('Gtk','4.0')
from gi.repository import Gtk,Gio,GLib
import controller


def configured():
    try:
        return json.loads((controller.STATE/'installed.json').read_text()).get('package_version')==json.loads((controller.PACKAGE/'package.json').read_text())['version']
    except (OSError,ValueError):return False


def launch():
    # Native GTK shell is optional in 0.2.0; Python window stays the default.
    if os.environ.get('TYPETUNE_NATIVE')=='1' and Path('/usr/bin/typetune-gui').exists():
        subprocess.Popen(['/usr/bin/typetune-gui'],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    else:
        subprocess.Popen(['/usr/bin/python3',str(controller.PACKAGE/'gui.py')],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)


class Setup(Gtk.ApplicationWindow):
    def __init__(self, app, runner=subprocess.run):
        super().__init__(application=app,title='Настройка TypeTune',default_width=560,default_height=450)
        self.runner=runner;self.busy=False
        self.set_titlebar(Gtk.HeaderBar())
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=16,margin_top=24,margin_bottom=24,margin_start=28,margin_end=28);self.set_child(box)
        heading=Gtk.Label(label='TypeTune для GNOME',xalign=0);heading.add_css_class('title-1');box.append(heading)
        box.append(Gtk.Label(label='Готовая сборка для Ubuntu 26.04 / GNOME 50. Настройка подключит расширение GNOME и сохранит ваши словари и параметры.',wrap=True,xalign=0))
        self.configure=Gtk.Button(label='Настроить TypeTune для моего пользователя');self.configure.add_css_class('suggested-action')
        self.configure.connect('clicked',lambda *_:self.run('configure'));box.append(self.configure)
        box.append(Gtk.Label(label='Режиму совместимости нужен доступ к клавиатуре и виртуальному вводу. Кнопка ниже добавляет вашу учётную запись в группу input: все программы этой учётной записи получат доступ к устройствам ввода. Потребуется системный пароль и повторный вход.',wrap=True,xalign=0))
        self.permissions=Gtk.Button(label='Разрешить доступ к устройствам ввода…');self.permissions.connect('clicked',lambda *_:self.run('permissions'));box.append(self.permissions)
        self.message=Gtk.Label(label='После первой настройки выйдите из сеанса и войдите снова.',wrap=True,xalign=0);box.append(self.message)
        self.remove=Gtk.Button(label='Удалить TypeTune — настройки сохранятся…');self.remove.connect('clicked',lambda *_:self.run('remove'));box.append(self.remove)
        self.open=Gtk.Button(label='Открыть TypeTune');self.open.set_sensitive(configured());self.open.connect('clicked',lambda *_:(launch(),self.close()));box.append(self.open)
        self.connect('close-request',lambda *_:self.busy)
    def run(self,action):
        if self.busy:return
        self.busy=True
        for button in (self.configure,self.permissions,self.remove,self.open):button.set_sensitive(False)
        self.message.set_label('Выполняется настройка…' if action=='configure' else 'Подтвердите системный запрос пароля…')
        def work():
            args=['/usr/bin/python3',str(controller.PACKAGE/'controller.py'),'package-configure'] if action=='configure' else ['/usr/bin/pkexec','/usr/lib/typetune-preview/manage-access','remove' if action=='remove' else 'input-access']
            try:
                result=self.runner(args,capture_output=True,text=True,timeout=180,check=False)
                message=(('Приложение удалено. Ваши настройки сохранены.' if action=='remove' else 'Готово. При первой установке выйдите из сеанса и войдите снова.') if result.returncode==0 else 'Настройка не завершена: '+(result.stderr.strip()[-600:] or 'системный запрос отменён'))
            except Exception as error:message='Ошибка настройки: '+str(error)
            GLib.idle_add(self.complete,message)
        threading.Thread(target=work,daemon=True).start()
    def complete(self,message):
        self.busy=False;self.message.set_label(message)
        self.configure.set_sensitive((controller.PACKAGE/'package.json').exists());self.permissions.set_sensitive((controller.PACKAGE/'package.json').exists());self.remove.set_sensitive((controller.PACKAGE/'package.json').exists());self.open.set_sensitive(configured());return False


def main():
    if os.getuid()==0:raise SystemExit('Откройте TypeTune от обычного пользователя')
    if configured() and '--setup' not in __import__('sys').argv:launch();return
    app=Gtk.Application(application_id='dev.kartamyshev.TypeTune.Setup')
    app.connect('activate',lambda app:Setup(app).present())
    app.run([])

if __name__=='__main__':main()
