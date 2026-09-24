#!/usr/bin/python3
"""GTK4 control window for the current Linux preview, via the shared controller."""
import threading
import sys
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib, Gio
from gui_model import request


class Window(Gtk.ApplicationWindow):
    def __init__(self, app, requester=request):
        super().__init__(application=app, title='TypeTune', default_width=540, default_height=740)
        self.requester = requester
        self.busy = False
        self.controls_busy = False
        self.pending = None
        self.rendering = False
        self.view = None
        self.closed = False
        self.state = None
        self.error_text = ''
        self.set_titlebar(Gtk.HeaderBar())
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18,
                      margin_top=24, margin_bottom=24, margin_start=28, margin_end=28)
        scroll = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.set_child(box); self.set_child(scroll)
        heading = Gtk.Label(label='TypeTune', xalign=0)
        heading.add_css_class('title-1'); box.append(heading)
        box.append(self.label('Исправление раскладки RU ↔ EN'))
        self.title = self.label('Получение состояния…'); self.title.add_css_class('title-2'); box.append(self.title)
        self.detail = self.label(''); box.append(self.detail)
        actions = Gtk.Box(spacing=10)
        self.pause = Gtk.Button(label='Пауза'); self.pause.connect('clicked', self.toggle_pause)
        self.stop = Gtk.Button(label='Остановить'); self.stop.connect('clicked', lambda _: self.dispatch('stop'))
        actions.append(self.pause); actions.append(self.stop); box.append(actions)
        self.start_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.start = Gtk.Button(label='Запустить TypeTune'); self.start.add_css_class('suggested-action')
        self.start.connect('clicked', lambda _: self.dispatch('start'))
        self.start_box.append(self.start); box.append(self.start_box)
        box.append(Gtk.Separator())
        auto_row = Gtk.Box(spacing=16)
        auto_text = self.label('Автокоррекция после пробела'); auto_text.set_hexpand(True)
        self.auto = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.auto.connect('state-set', self.toggle_auto)
        auto_row.append(auto_text); auto_row.append(self.auto); box.append(auto_row)
        self.manual = self.add_switch(box, 'Ручное переключение (Double Shift)', 'manual-toggle', 'manual_switching')
        self.switch_last = self.add_switch(box, 'Переключать только последнее слово', 'switch-last-toggle', 'switch_only_last_word')
        self.dont_words = self.add_switch(box, 'Не переключать слова', 'dont-switch-toggle', 'dont_switch_words')
        self.anti_loop = self.add_switch(box, 'Не исправлять после смены раскладки', 'anti-loop-toggle', 'dont_correct_after_layout_change')
        self.sound = self.add_switch(box, 'Звук переключения', 'sound-toggle', 'play_switching_sound')
        self.show_flag = self.add_switch(box, 'Показывать флаг раскладки', 'flag-toggle', 'display_layout_flag')
        login_row = Gtk.Box(spacing=16)
        login_text = self.label('Запускать при входе в систему'); login_text.set_hexpand(True)
        self.login = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.login.connect('state-set', self.toggle_login)
        login_row.append(login_text); login_row.append(self.login); box.append(login_row)
        threshold_row = Gtk.Box(spacing=16)
        threshold_text = self.label('Подтверждений перед предложением (1–10)'); threshold_text.set_hexpand(True)
        self.threshold = Gtk.SpinButton.new_with_range(1, 10, 1)
        self.threshold.set_valign(Gtk.Align.CENTER)
        self.threshold.connect('value-changed', self.change_threshold)
        threshold_row.append(threshold_text); threshold_row.append(self.threshold); box.append(threshold_row)
        self.boards = self.label('Активные раскладки: us, ru')
        self.boards.add_css_class('dim-label'); box.append(self.boards)
        box.append(self.label('Double Shift — переключить последнее слово и язык ввода. Повторите жест, чтобы переключить обратно.'))
        self.notice = self.label('Режим совместимости не распознаёт парольные поля и выделение. Для паролей и команд используйте паузу. Не все приложения обрабатывают замену одинаково.')
        self.notice.add_css_class('dim-label'); box.append(self.notice)
        self.error = self.label(''); self.error.add_css_class('error'); self.error.set_selectable(True); box.append(self.error)
        words = Gtk.Button(label='Слова и исключения…')
        words.connect('clicked', self.open_words)
        box.append(words)
        self.word_editor = None
        self.suggestion_editor = None
        self.suggestions = Gtk.Button(label='Предложения для словаря…')
        self.suggestions.connect('clicked', self.open_suggestions)
        box.append(self.suggestions)
        self.application_editor = None
        apps = Gtk.Button(label='Исключения приложений…')
        apps.connect('clicked', self.open_applications)
        box.append(apps)
        from pathlib import Path
        if (Path(__file__).parent/'package.json').is_file():
            setup=Gtk.Button(label='Установка, доступ и удаление…')
            def open_setup(*_):
                import subprocess
                subprocess.Popen(['/usr/bin/typetune-preview','--setup'],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
            setup.connect('clicked',open_setup);box.append(setup)
        self.refresh = Gtk.Button(label='Обновить состояние')
        self.refresh.connect('clicked', lambda _: self.dispatch('status', explicit=True)); box.append(self.refresh)
        footer = self.label('Закрытие окна не останавливает TypeTune. Режим, автокоррекция и словари сохраняются. Пауза действует в текущем сеансе.')
        footer.add_css_class('dim-label'); box.append(footer)
        self.connect('close-request', self.closing)
        self.timer = GLib.timeout_add_seconds(3, self.poll)
        self.render()
        self.dispatch('status')

    def open_words(self, *_):
        from word_editor import WordEditor
        if self.word_editor is None:
            self.word_editor = WordEditor(self)
        self.word_editor.present()

    def show_page(self, page):
        """Tray openers: focus the matching editor or the permissions CTA."""
        if page == 'learned':
            self.open_words()
        elif page == 'auto-disabled':
            self.open_applications()
        elif page == 'active-keyboards':
            self.present()
        elif page == 'permissions':
            self.present()
            if getattr(self.state, 'needs_permissions', False):
                self.error_text = 'Нет доступа к /dev/input — откройте «Установка, доступ и удаление…» и подтвердите polkit.'
                self.render()

    def open_suggestions(self, *_):
        from suggestion_editor import SuggestionEditor
        if self.suggestion_editor is None:
            self.suggestion_editor = SuggestionEditor(self)
        self.suggestion_editor.present()

    def open_applications(self, *_):
        from application_editor import ApplicationEditor
        if self.application_editor is None:
            self.application_editor = ApplicationEditor(self)
        self.application_editor.present()

    @staticmethod
    def label(text):
        return Gtk.Label(label=text, xalign=0, wrap=True)

    def add_switch(self, parent, text, command, attr):
        row = Gtk.Box(spacing=16)
        label = self.label(text); label.set_hexpand(True)
        switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        switch.connect('state-set', self.toggle_setting, command, attr)
        row.append(label); row.append(switch); parent.append(row)
        return switch

    def toggle_setting(self, _, enabled, command, attr):
        if self.rendering or self.controls_busy or self.state is None:
            return True
        if not (self.state.running or self.state.configurable):
            return True
        if enabled == getattr(self.state, attr):
            return True
        self.dispatch(command)
        return True

    def closing(self, *_):
        app = self.get_application()
        tray = getattr(app, 'tray', None)
        if tray and tray.registered:
            self.set_visible(False)
            return True
        if tray:
            app.quit()
        self.closed = True
        GLib.source_remove(self.timer)
        return False

    def poll(self):
        if not self.closed and not self.busy:
            self.dispatch('status')
        return not self.closed

    def toggle_pause(self, *_):
        if self.state:
            self.dispatch('pause' if self.state.enabled else 'resume')

    def toggle_auto(self, _, enabled):
        if not self.rendering and not self.controls_busy and self.state and (self.state.running or self.state.configurable) and enabled != self.state.automatic:
            self.dispatch('auto-on' if enabled else 'auto-off')
        return True  # Reflect only the confirmed value, not an optimistic toggle.

    def toggle_login(self, _, enabled):
        if not self.rendering and not self.controls_busy and self.state and self.state.configurable and enabled != self.state.autostart:
            self.dispatch('autostart-on' if enabled else 'autostart-off')
        return True

    def change_threshold(self, spin):
        if self.rendering or self.controls_busy or self.state is None:
            return True
        value = spin.get_value_as_int()
        if value != self.state.learn_threshold:
            self.dispatch('threshold-set', payload=str(value))
        return True


    def render(self):
        view = (self.state, self.error_text, self.controls_busy)
        if view == self.view:
            return
        self.view = view
        self.rendering = True
        state = self.state
        if state:
            self.suggestions.set_label(f'Предложения для словаря ({state.suggestion_count})…')
            self.title.set_label(state.title)
            self.detail.set_label(state.detail)
            self.pause.set_label('Пауза' if state.enabled else 'Продолжить')
            self.auto.set_state(state.automatic)
            self.auto.set_active(state.automatic)
            self.login.set_state(state.autostart)
            self.login.set_active(state.autostart)
            self.threshold.set_value(state.learn_threshold)
            boards = ', '.join(state.active_keyboards) or '—'
            self.boards.set_label(f'Активные раскладки: {boards}')
            for switch, attr in ((self.manual, 'manual_switching'),
                                 (self.switch_last, 'switch_only_last_word'),
                                 (self.dont_words, 'dont_switch_words'),
                                 (self.anti_loop, 'dont_correct_after_layout_change'),
                                 (self.sound, 'play_switching_sound'),
                                 (self.show_flag, 'display_layout_flag')):
                value = getattr(state, attr)
                switch.set_state(value)
                switch.set_active(value)
        self.start_box.set_visible(not state or not state.running)
        self.pause.set_visible(bool(state and state.running))
        self.stop.set_visible(state is None or state.running)
        self.pause.set_sensitive(bool(state and state.running and not self.controls_busy))
        self.auto.set_sensitive(bool(state and (state.running or state.configurable) and not self.controls_busy))
        policy_sensitive = bool(state and (state.running or state.configurable) and not self.controls_busy)
        for switch in (self.manual, self.switch_last, self.dont_words, self.anti_loop, self.sound, self.show_flag):
            switch.set_sensitive(policy_sensitive)
        self.login.set_sensitive(bool(state and state.configurable and not self.controls_busy))
        self.threshold.set_sensitive(bool(state and state.configurable and not self.controls_busy))
        self.start.set_sensitive(bool(state and state.can_start and not self.controls_busy))
        self.stop.set_sensitive(not self.controls_busy)
        self.refresh.set_sensitive(not self.controls_busy)
        self.error.set_label(self.error_text)
        self.error.set_visible(bool(self.error_text))

        self.rendering = False
        tray = getattr(self.get_application(), 'tray', None)
        if tray:
            tray.update(self.state, self.error_text, self.controls_busy)

    def dispatch(self, command, explicit=False, payload=None):
        if self.closed: return
        if self.busy:
            if command != 'status' and not self.controls_busy:
                self.pending = (command, explicit, payload)
                self.controls_busy = True
                self.render()
            return
        self.busy = True
        self.controls_busy = command != 'status'
        if command != 'status' or explicit: self.error_text = ''
        self.render()
        def work():
            try:
                state, error = self.requester(command, payload)
            except Exception as exc:
                state, error = None, f'Не удалось получить состояние: {exc}'
            GLib.idle_add(self.complete, state, error)
        threading.Thread(target=work, daemon=True).start()

    def complete(self, state, error):
        if self.closed: return False
        self.state = state
        if error: self.error_text = error
        if state is None:
            self.title.set_label('Нет связи с TypeTune')
            self.detail.set_label('Проверьте состояние повторно. Последняя команда могла успеть выполниться.')
        self.busy = False
        if self.pending:
            command, explicit, payload = self.pending
            self.pending = None
            self.dispatch(command, explicit, payload)
        else:
            self.controls_busy = False
            self.render()
        return False


def main(background=False):
    from tray import Tray
    app = Gtk.Application(application_id='dev.kartamyshev.TypeTune.Preview', flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE)
    def startup(app):
        app.hold()
        app.window = Window(app)
        app.tray = Tray(app.get_dbus_connection(), app.window)
    def command_line(app, command):
        if '--background' not in command.get_arguments():
            app.window.present()
        return 0
    def shutdown(app):
        app.tray.close()
        if not app.window.closed:
            app.window.closed = True
            GLib.source_remove(app.window.timer)
    app.connect('startup', startup)
    app.connect('command-line', command_line)
    app.connect('activate', lambda app: app.window.present())
    app.connect('shutdown', shutdown)
    return app.run(['typetune-gui'] + (['--background'] if background else []))


if __name__ == '__main__':
    raise SystemExit(main('--background' in sys.argv[1:]))
