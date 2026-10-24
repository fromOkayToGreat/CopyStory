#!/usr/bin/env python3
"""Offline policy tests: mocked system tools and temporary synthetic bundle bytes.
No certificates, signing, keychain, application execution, clipboard or user data.
"""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('development_audit', ROOT/'scripts/verify-development.py')
audit_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_module)
build_spec = importlib.util.spec_from_file_location('development_build', ROOT/'scripts/build-signed-development.py')
build_module = importlib.util.module_from_spec(build_spec)
build_spec.loader.exec_module(build_module)


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='copystory-offline-signing-')
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name)/'Synthetic.app'
        (self.app/'Contents/MacOS').mkdir(parents=True)
        (self.app/'Contents/MacOS/CopyStory').write_bytes(b'inert synthetic bytes; never executable')
        self.info = dict(CFBundleIdentifier='com.copystory.development', CFBundleExecutable='CopyStory',
            CopyStoryDevelopmentBuild=True, CopyStorySourceDirty='clean', CopyStorySourceRevision='a'*40,
            CopyStoryBuildConfiguration='Debug', CFBundleShortVersionString='1.0.0', CFBundleVersion='2',
            LSMinimumSystemVersion='26.0')
        self.save()
        self.authority = 'Apple Development: Synthetic Developer (SYNTHETIC1)'
        self.team = 'SYNTHETIC1'
        self.dr = 'identifier "com.copystory.development" and anchor apple generic'
        self.verify_exit = 0
        self.queries = []
        self.identity = None

    def save(self):
        (self.app/'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))

    def fake_run(self, args):
        self.queries.append(args)
        stdout = ''
        if '--verbose=4' in args:
            stdout = ('Authority='+self.authority+'\nTeamIdentifier='+self.team+
                      '\nCodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1')
        elif '-r-' in args:
            stdout = '# designated => '+self.dr
        elif '-archs' in args:
            stdout = 'arm64'
        elif '-L' in args:
            stdout = 'system frameworks only'
        elif '--extract-certificates' in args:
            # codesign's optional long-option value must be attached with '='.
            return dict(exit=1, stdout='', stderr='Prefix was interpreted as a target path')
        elif any(arg.startswith('--extract-certificates=') for arg in args):
            option = next(arg for arg in args if arg.startswith('--extract-certificates='))
            Path(option.split('=', 1)[1]+'0').write_bytes(b'public synthetic certificate')
        return dict(exit=self.verify_exit if '--verify' in args else 0, stdout=stdout, stderr='')

    def inspect(self, **kwargs):
        import hashlib
        defaults = dict(signed=True, team='SYNTHETIC1', revision='a'*40, build='2',
                        identity=hashlib.sha1(b'public synthetic certificate').hexdigest())
        defaults.update(kwargs)
        ent = subprocess.CompletedProcess([], 0, plistlib.dumps({'com.apple.security.app-sandbox': True}), b'')
        with patch.object(audit_module, 'run', side_effect=self.fake_run), patch.object(audit_module.subprocess, 'run', return_value=ent):
            return audit_module.audit(self.app, **defaults)

    def test_exact_signed_metadata_and_certificate_accepted(self):
        self.assertEqual(self.inspect()['staticVerdict'], 'PASS')

    def test_public_certificate_extraction_uses_attached_prefix_argument(self):
        # The fake tool rejects the historical split form, as real codesign did.
        result = self.inspect()
        self.assertEqual(result['staticVerdict'], 'PASS')
        self.assertTrue(result['checks']['exactCertificate'])
        extraction = [args for args in self.queries
                      if any(arg.startswith('--extract-certificates') for arg in args)]
        self.assertEqual(len(extraction), 1)
        command = extraction[0]
        self.assertEqual(command[:2], ['/usr/bin/codesign', '-d'])
        self.assertEqual(len(command), 4)  # One option value, then one bundle target.
        self.assertTrue(command[2].startswith('--extract-certificates='))
        self.assertTrue(command[2].split('=', 1)[1])
        self.assertEqual(command[3], str(self.app.resolve()))

    def test_wrong_team_and_distribution_channel_rejected(self):
        self.team = 'OTHERTEAM1'
        self.authority = 'Developer ID Application: Synthetic'
        result = self.inspect()
        self.assertFalse(result['checks']['team'])
        self.assertFalse(result['checks']['appleDevelopment'])
        self.assertEqual(result['staticVerdict'], 'FAIL')

    def test_hash_only_requirement_rejected(self):
        self.dr = 'cdhash H"'+'a'*40+'"'
        self.assertFalse(self.inspect()['checks']['stableRequirement'])

    def test_wrong_certificate_rejected(self):
        self.assertFalse(self.inspect(identity='0'*40)['checks']['exactCertificate'])

    def test_wrong_revision_build_dirty_and_fixture_rejected(self):
        self.info.update(CopyStorySourceDirty='dirty', CopyStorySourceRevision='b'*40,
                         CFBundleVersion='1', CopyStoryEngineeringOnly=True)
        self.save()
        checks = self.inspect()['checks']
        self.assertTrue(all(not checks[k] for k in ('cleanSource', 'expectedRevision', 'expectedBuild', 'noFixtureMarkers')))

    def test_dirty_provenance_is_allowed_only_in_default_mode(self):
        self.info['CopyStorySourceDirty'] = 'dirty'
        self.save()
        default = self.inspect(signed=False, team=None, revision=None, build=None, identity=None)
        self.assertEqual(default['staticVerdict'], 'PASS')
        self.assertTrue(default['checks']['sourceState'])
        self.assertNotIn('cleanSource', default['checks'])
        signed = self.inspect()
        self.assertEqual(signed['staticVerdict'], 'FAIL')
        self.assertEqual([key for key, passed in signed['checks'].items() if not passed],
                         ['cleanSource'])

    def test_unknown_provenance_rejected_in_both_modes(self):
        for state in (None, '', 'unknown'):
            self.info['CopyStorySourceDirty'] = state
            if state is None:
                self.info.pop('CopyStorySourceDirty')
            self.save()
            with self.subTest(state=state):
                default = self.inspect(signed=False, team=None, revision=None, build=None, identity=None)
                self.assertEqual(default['staticVerdict'], 'FAIL')
                self.assertFalse(default['checks']['sourceState'])
                self.assertEqual(self.inspect()['staticVerdict'], 'FAIL')

    def test_signature_verification_failure_rejected(self):
        self.verify_exit = 3
        self.assertFalse(self.inspect()['checks']['strictSignature'])

    def test_extra_entitlement_rejected(self):
        ent = subprocess.CompletedProcess([], 0, plistlib.dumps({'com.apple.security.app-sandbox': True,
                  'com.apple.security.cs.disable-library-validation': True}), b'')
        with patch.object(audit_module, 'run', side_effect=self.fake_run), patch.object(audit_module.subprocess, 'run', return_value=ent):
            self.assertFalse(audit_module.audit(self.app)['checks']['sandboxOnly'])

    def test_continuity_is_two_way_and_build_must_increase(self):
        result = self.inspect(previous=self.app)
        self.assertFalse(result['checks']['buildIncreases'])
        cross = [args for args in self.queries if '-R' in args]
        self.assertEqual(len(cross), 2)
        self.assertTrue(all(args[args.index('-R')+1].startswith('=identifier ') for args in cross))

    def test_inventory_preserves_symlink_and_rejects_escape(self):
        (self.app/'internal').symlink_to('Contents')
        entries = audit_module.inventory(self.app)
        self.assertTrue(any(e.get('target') == 'Contents' for e in entries))
        (self.app/'escape').symlink_to('../outside')
        with self.assertRaisesRegex(ValueError, 'External'):
            audit_module.inventory(self.app)

    def test_cli_signed_mode_requires_exact_expectations(self):
        result = subprocess.run(['python3', str(ROOT/'scripts/verify-development.py'), str(self.app), '--signed'], capture_output=True)
        self.assertEqual(result.returncode, 2)

    def test_build_cli_rejects_missing_transition_and_build_one(self):
        script = str(ROOT/'scripts/build-signed-development.py')
        base = ['python3', script, '--team', 'SYNTHETIC1', '--identity', 'a'*40,
                '--build', '1', '--output', str(Path(self.temp.name)/'not-created')]
        for extra in ([], ['--initial-signed-baseline']):
            self.assertEqual(subprocess.run(base+extra, capture_output=True).returncode, 2)
        self.assertFalse((Path(self.temp.name)/'not-created').exists())

    def test_identity_gate_rejects_developer_id_before_signing(self):
        sha = 'a'*40
        for name in ('Developer ID Application: Synthetic', 'Apple Distribution: Synthetic'):
            with patch.object(build_module.subprocess, 'check_output', return_value=f'  1) {sha} "{name}"\n'):
                with self.assertRaisesRegex(ValueError, 'Apple Development'):
                    build_module.require_development_identity(sha)
        with patch.object(build_module.subprocess, 'check_output', return_value=f'  1) {sha.upper()} "Apple Development: Synthetic"\n'):
            build_module.require_development_identity(sha)

    def test_plan_only_makes_no_build_or_output(self):
        from types import SimpleNamespace
        output = Path(self.temp.name)/'dry-plan'
        args = SimpleNamespace(output=output, team='SYNTHETIC1', identity='a'*40, build='2',
            execute_signing=False, initial_signed_baseline=True, previous=None)
        with patch.object(build_module.subprocess, 'check_output', side_effect=['b'*40, ' M synthetic']):
            result = build_module.plan(args, '/Applications/Xcode.app/Contents/Developer')
        self.assertEqual(result['mode'], 'plan-only')
        self.assertTrue(result['sourceDirty'])
        self.assertNotIn('-allowProvisioningUpdates', result['command'])
        self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
