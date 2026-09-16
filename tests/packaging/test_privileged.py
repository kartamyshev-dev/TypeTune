import os,runpy,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]

class Checks(unittest.TestCase):
    def invoke(self,action):
        with patch('os.geteuid',return_value=0),patch.dict(os.environ,PKEXEC_UID='1000'),patch('pwd.getpwuid',return_value=SimpleNamespace(pw_name='fixture')),patch('sys.argv',['manage-access',*action]),patch('subprocess.run') as run:
            runpy.run_path(str(ROOT/'packaging/preview/manage-access'),run_name='__main__')
            return [call.args[0] for call in run.call_args_list]
    def test_fixed_privileged_actions_and_unknown_rejected(self):
        commands=self.invoke(['input-access'])
        self.assertIn(['/usr/sbin/usermod','-aG','input','--','fixture'],commands)
        self.assertEqual(self.invoke(['remove']),[['/usr/bin/apt-get','-y','remove','typetune-preview']])
        for action in [[],['shell'],['remove','other-package'],['input-access','root']]:
            with self.assertRaises(SystemExit):self.invoke(action)
    def test_isolated_dpkg_hook_cannot_touch_host_sessions(self):
        with patch.dict(os.environ,DPKG_ROOT='/tmp/fixture'),patch('subprocess.run') as run:
            with self.assertRaises(SystemExit) as result:runpy.run_path(str(ROOT/'packaging/preview/session-lifecycle'),run_name='__main__')
            self.assertEqual(result.exception.code,0);run.assert_not_called()
