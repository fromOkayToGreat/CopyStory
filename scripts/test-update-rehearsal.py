#!/usr/bin/env python3
"""Exercise isolation and fail-closed production boundaries without credentials."""
import base64
import importlib.util
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

prepare = load(ROOT / 'scripts/prepare-update-rehearsal.py', 'prepare')
policy = load(ROOT / 'scripts/release_policy.py', 'policy')

class RehearsalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base = ROOT / '.build/update-rehearsals'
        base.mkdir(parents=True, exist_ok=True)
        cls.container = Path(tempfile.mkdtemp(prefix='unit-', dir=base))
        cls.key = base64.b64encode(bytes(range(32))).decode()  # Public fixture only; no signing key.
        cls.workspace = prepare.prepare(cls.container / 'run', 'example/CopyStory-QA', cls.key)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.container)

    def test_isolated_identity_storage_feed_and_key(self):
        for label, build in [('A', '1'), ('B', '2')]:
            root = self.workspace / label
            p = plistlib.loads((root / 'Config/Info.plist').read_bytes())
            self.assertEqual(p['CFBundleIdentifier'], 'com.copystory.rehearsal')
            self.assertEqual(p['CFBundleVersion'], build)
            self.assertEqual(p['SUPublicEDKey'], self.key)
            self.assertIn('/example/CopyStory-QA/releases/download/rehearsal-feed/', p['SUFeedURL'])
            self.assertIn('appendingPathComponent("CopyStory Rehearsal",', (root / 'Sources/CopyStory/CopyStoryApp.swift').read_text())
            generated = load(root / 'scripts/release_policy.py', 'generated' + label)
            self.assertEqual(generated.info()['CFBundleVersion'], build)
            with self.assertRaises(ValueError):
                policy.info(root / 'Config/Info.plist')
            service = (root / 'Sources/CopyStory/UpdateService.swift').read_text()
            self.assertIn('parts[2] == "CopyStory-QA"', service)
            self.assertIn('"com.copystory.rehearsal"', service)
            self.assertNotIn('releases/latest/download', service)
            self.assertTrue(p['SURequireSignedFeed'])
            self.assertTrue(p['SUVerifyUpdateBeforeExtraction'])
            self.assertEqual(p['SUSignedFeedFailureExpirationInterval'], 0)
            self.assertNotIn('CopyStoryDevelopmentBuild', p)
            self.assertIn('--account com.copystory.rehearsal.sparkle', (root / 'scripts/release.sh').read_text())
            for helper in ['publish-release.sh', 'install.sh']:
                self.assertNotEqual(subprocess.run(['bash', str(root / 'scripts' / helper)], capture_output=True).returncode, 0)

    def test_refuses_production_configuration_and_overwrite(self):
        for repo, key in [('fromOkayToGreat/CopyStory', self.key),
                          ('FROMOKAYTOGREAT/COPYSTORY', self.key),
                          ('example/QA', policy.info()['SUPublicEDKey']),
                          ('example/QA', 'bad'), ('example/QA;bad', self.key)]:
            with self.assertRaises(ValueError):
                prepare.prepare(self.container / 'invalid', repo, key)
        with self.assertRaises(FileExistsError):
            prepare.prepare(self.workspace, 'example/QA', self.key)
        with self.assertRaises(ValueError):
            prepare.prepare(ROOT / 'unsafe-output', 'example/QA', self.key)

    def test_production_marker_rejected_even_with_production_identity(self):
        p = policy.info()
        p['CopyStoryUpdateRehearsal'] = True
        path = self.container / 'marked.plist'
        path.write_bytes(plistlib.dumps(p))
        with self.assertRaises(ValueError):
            policy.info(path)

if __name__ == '__main__':
    unittest.main()
