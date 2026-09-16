import json
import subprocess
import unittest
from gui_model import describe, request


def state(**changes):
    runtime = dict(enabled=True, automatic=True, available=True, mode='ru')
    runtime.update(changes)
    return dict(installed=True, bridge=True, compatibility=runtime, runtime='not-running')


class Checks(unittest.TestCase):
    def test_confirmed_and_unknown_capabilities(self):
        self.assertEqual(describe(state()).title, 'Работает')
        self.assertEqual(describe(state(enabled=False)).title, 'На паузе')
        self.assertEqual(describe(state(available=None)).title, 'Ожидает подходящее поле')
        self.assertFalse(describe(dict(installed=True, bridge=None)).can_start)
        self.assertTrue(describe(dict(installed=True, bridge=True)).can_start)
        self.assertFalse(describe({}).can_start)
        self.assertEqual(describe(dict(runtime=state()['compatibility'])).backend, 'IBus')
        with self.assertRaises(ValueError): describe(state(enabled=None))

    def test_mutation_is_followed_by_effective_state(self):
        calls = []
        def runner(argv, **kwargs):
            calls.append(argv[-1])
            return subprocess.CompletedProcess(argv, 0, json.dumps(state(enabled=False)), '')
        current, error = request('pause', runner)
        self.assertEqual(calls, ['pause', 'status'])
        self.assertFalse(current.enabled)
        self.assertIsNone(error)

    def test_unconfirmed_success_is_an_error(self):
        def runner(argv, **kwargs):
            return subprocess.CompletedProcess(argv, 0, json.dumps(state()), '')
        current, error = request('pause', runner)
        self.assertTrue(current.enabled)
        self.assertIn('не подтверждено', error)

    def test_failure_and_timeout_still_refresh_state(self):
        for timeout in (False, True):
            calls = []
            def runner(argv, **kwargs):
                calls.append(argv[-1])
                if argv[-1] == 'pause':
                    if timeout: raise subprocess.TimeoutExpired(argv, 25)
                    return subprocess.CompletedProcess(argv, 1, '', 'failure')
                return subprocess.CompletedProcess(argv, 0, json.dumps(state()), '')
            current, error = request('pause', runner)
            self.assertEqual(calls, ['pause', 'status'])
            self.assertTrue(current.enabled)
            self.assertTrue(error)

    def test_invalid_status_and_commands_do_not_fake_success(self):
        def runner(argv, **kwargs):
            return subprocess.CompletedProcess(argv, 0, 'invalid', '')
        with self.assertRaises(ValueError): request('status', runner)
        with self.assertRaises(ValueError): request('uninstall', runner)

    def test_saved_settings_and_effective_runtime_remain_distinct(self):
        data=state()
        data['settings']=dict(mode='ibus',automatic=False,autostart_effective=True)
        live=describe(data)
        self.assertTrue(live.automatic)  # runtime readback wins over saved intent
        self.assertTrue(live.autostart)
        self.assertEqual(live.saved_mode,'ibus')
        data['compatibility']='not-running'
        stopped=describe(data)
        self.assertFalse(stopped.automatic)
        self.assertTrue(stopped.configurable)
        data['settings_error']='Повреждён файл настроек'
        broken=describe(data)
        self.assertFalse(broken.configurable)
        self.assertFalse(broken.can_start)

    def test_app_exclusion_reason_does_not_change_global_switch(self):
        current=describe(state(automatic_blocked='excluded-application'))
        self.assertTrue(current.automatic)
        self.assertIn('для этого приложения',current.detail)
        self.assertIn('определения приложения',describe(state(automatic_blocked='unknown-application')).detail)
