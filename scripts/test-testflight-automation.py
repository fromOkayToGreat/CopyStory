#!/usr/bin/env python3
"""Offline import-policy tests; no app execution, permissions or clipboard."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('beta_imports', ROOT/'scripts/verify-testflight-automation.py')
beta = importlib.util.module_from_spec(spec)
spec.loader.exec_module(beta)


class BetaPolicyTests(unittest.TestCase):
    def test_fixed_pid_posting_is_allowed_but_global_or_field_automation_is_not(self):
        for name in beta.REQUIRED:
            self.assertIsNone(beta.FORBIDDEN.search(' U '+name+'\n'))
        for name in ['_CGEventPost', '_CGEventPostToPSN', '_CGEventTapCreate', '_CGEventCreateMouseEvent',
                     '_AXUIElementCreateApplication', '_AXIsProcessTrusted', '_AXObserverCreate',
                     '_CGRequestListenEventAccess']:
            self.assertIsNotNone(beta.FORBIDDEN.search(' U '+name+'\n'), name)

    def test_copy_only_or_development_bundle_cannot_pass_beta_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)/'Synthetic.app'
            (app/'Contents').mkdir(parents=True)
            for info in [dict(CFBundleIdentifier='com.copystory.development'),
                         dict(CFBundleIdentifier='com.copystory.app', CopyStoryBuildConfiguration='Production', CopyStoryProductionBuild=True)]:
                (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
                with self.assertRaisesRegex(ValueError, 'explicit TestFlight'):
                    beta.verify(app)


if __name__ == '__main__':
    unittest.main()
