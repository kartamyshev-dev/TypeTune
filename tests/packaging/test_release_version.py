import runpy
import unittest
from pathlib import Path

version = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'scripts/release-version.py'))['version']


class Checks(unittest.TestCase):
    def test_only_semver_tags_are_publishable(self):
        self.assertEqual(version('refs/tags/v0.1.0', 'v0.1.0'), '0.1.0')
        self.assertEqual(version('refs/tags/v1.2.3', 'v1.2.3'), '1.2.3')
        self.assertEqual(version('refs/heads/main', 'main'), '0.1.0')
        for tag in (
            'v1.0.0-preview1-1',
            'v1.0.0\nENV=bad',
            'v1.0.0;echo BAD',
            'v1.0',
            '1.0.0',
        ):
            with self.assertRaises(ValueError):
                version('refs/tags/' + tag, tag)


if __name__ == '__main__':
    unittest.main()
