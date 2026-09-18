import runpy,unittest
from pathlib import Path
version=runpy.run_path(str(Path(__file__).resolve().parents[2]/'scripts/release-version.py'))['version']
class Checks(unittest.TestCase):
    def test_only_documented_tag_format_is_publishable(self):
        self.assertEqual(version('refs/tags/v0.1.0-preview52-1','v0.1.0-preview52-1'),'0.1.0~preview52-1')
        self.assertEqual(version('refs/heads/main','main'),'0.1.0~preview55-2')
        for tag in ('v1.0.0','v1.0.0-preview1-1\nENV=bad','v1.0.0-preview1-1;echo BAD'):
            with self.assertRaises(ValueError):version('refs/tags/'+tag,tag)
