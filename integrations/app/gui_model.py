"""Presentation of confirmed controller state; no GTK or input access."""
from dataclasses import dataclass, replace
import json
from pathlib import Path
import subprocess


@dataclass(frozen=True)
class State:
    title: str
    detail: str
    running: bool = False
    enabled: bool = False
    automatic: bool = False
    can_start: bool = False
    backend: str = ''
    autostart: bool = False
    configurable: bool = False
    suggestion_count: int = 0
    learn_threshold: int = 3
    flag: str = '?'
    display_layout_flag: bool = True
    manual_switching: bool = True
    switch_only_last_word: bool = True
    dont_switch_words: bool = False
    dont_correct_after_layout_change: bool = True
    play_switching_sound: bool = False
    needs_permissions: bool = False
    active_keyboards: tuple = ('us', 'ru')


def _describe(data):
    if not isinstance(data, dict):
        raise ValueError('Некорректный ответ controller')
    runtime = data.get('compatibility')
    backend = 'Режим совместимости'
    if isinstance(runtime, dict):
        if not all(type(runtime.get(key)) is bool for key in ('enabled', 'automatic')):
            raise ValueError('Runtime не сообщил состояние настроек')
        enabled = runtime.get('enabled') is True
        automatic = runtime.get('automatic') is True
        available = runtime.get('available') is True
        title = 'На паузе' if not enabled else ('Работает' if available else 'Ожидает подходящее поле')
        mode = {'us': 'EN', 'ru': 'RU'}.get(runtime.get('mode'), 'не определён')
        detail = f'{backend} · Язык: {mode}'
        if runtime.get('words_error'): detail += '\n' + runtime['words_error']
        if runtime.get('applications_error'): detail += '\n' + runtime['applications_error']
        reason = runtime.get('automatic_blocked')
        if automatic and reason == 'excluded-application':
            detail += '\nАвтокоррекция выключена для этого приложения. Double Shift доступен.'
        elif automatic and reason == 'unknown-application':
            detail += '\nАвтокоррекция ждёт определения приложения для проверки исключений.'
        needs_permissions = runtime.get('devices') == 0
        if enabled and not available:
            if needs_permissions:
                detail += '\nНет доступа к /dev/input — откройте «Настроить доступ».'
            else:
                detail += '\nКоррекция сейчас недоступна. Проверьте раскладку, активное поле и подключение клавиатуры.'
        from flag_badge import label
        return State(title, detail, True, enabled, automatic, False, backend,
                     suggestion_count=runtime.get('suggestion_count', 0),
                     flag=label(runtime.get('mode')),
                     needs_permissions=needs_permissions)
    if data.get('installed') is not True:
        return State('Нужна установка', 'Установите Linux preview по инструкции в README проекта.')
    if data.get('bridge') is not True:
        return State('Нет связи с GNOME', 'После установки выйдите из сеанса и войдите снова. Проверьте расширение TypeTune Session.')
    return State('Остановлен', 'Запустите TypeTune, чтобы исправлять раскладку в приложениях.', can_start=True)


def describe(data):
    state = _describe(data)
    settings = data.get('settings', {})
    detail = state.detail
    if data.get('settings_error'): detail += '\n' + data['settings_error']
    if settings.get('autostart_mismatch'): detail += '\nАвтозапуск не настроен: выключите и включите переключатель повторно.'
    return replace(state, detail=detail, can_start=state.can_start and not data.get('settings_error'),
        automatic=state.automatic if state.running else settings.get('automatic', True) is True,
        autostart=settings.get('autostart_effective') is True,
        learn_threshold=settings.get('learn_threshold', 3) if type(settings.get('learn_threshold', 3)) is int else 3,
        display_layout_flag=settings.get('display_layout_flag', True) is not False,
        manual_switching=settings.get('manual_switching', True) is not False,
        switch_only_last_word=settings.get('switch_only_last_word', True) is not False,
        dont_switch_words=settings.get('dont_switch_words', False) is True,
        dont_correct_after_layout_change=settings.get('dont_correct_after_layout_change', True) is not False,
        play_switching_sound=settings.get('play_switching_sound', False) is True,
        active_keyboards=tuple(b for b in settings.get('active_keyboards', ['us', 'ru']) if isinstance(b, str)),
        configurable=data.get('installed') is True and not data.get('settings_error'))


COMMANDS = {'status', 'compat-on', 'start', 'pause', 'resume', 'stop', 'auto-on', 'auto-off',
            'autostart-on', 'autostart-off', 'threshold-set', 'manual-toggle', 'switch-last-toggle',
            'dont-switch-toggle', 'anti-loop-toggle', 'sound-toggle', 'flag-toggle', 'quit'}


def request(command, payload=None, runner=subprocess.run):
    """Called only on a worker. Confirm every mutation by reading effective state."""
    if command not in COMMANDS:
        raise ValueError('Неизвестная команда')
    controller = Path(__file__).with_name('controller.py')
    def run(action, text=None):
        result = runner(['/usr/bin/python3', str(controller), action], capture_output=True,
                        text=True, timeout=25, check=False, input=text)
        if result.returncode:
            raise RuntimeError((result.stderr or result.stdout or 'Controller завершился с ошибкой').strip()[-1600:])
        return result.stdout
    error = None
    if command != 'status':
        try:
            run(command, payload)
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
            error = str(exc)
    data = json.loads(run('status'))
    state = describe(data)
    if not error:
        expected = {'pause': not state.enabled and state.running,
                    'resume': state.enabled and state.running,
                    'auto-on': state.automatic,
                    'auto-off': not state.automatic,
                    'autostart-on': state.autostart,
                    'autostart-off': not state.autostart,
                    'stop': not state.running,
                    'quit': not state.running,
                    'compat-on': state.running and state.backend == 'Режим совместимости',
                    'start': state.running and state.backend == 'Режим совместимости'}
        if command in expected and not expected[command]:
            error = 'Изменение не подтверждено. Показано фактическое состояние.'
        if command == 'threshold-set':
            try: wanted = int((payload or '').strip())
            except ValueError: wanted = None
            if wanted is None or state.learn_threshold != wanted:
                error = 'Изменение не подтверждено. Показано фактическое состояние.'
    return state, error
