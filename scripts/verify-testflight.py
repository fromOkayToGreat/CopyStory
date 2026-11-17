#!/usr/bin/env python3
"""Inspect an unsigned preparation or signed TestFlight app; never execute it."""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('beta_automation', ROOT/'scripts/verify-testflight-automation.py')
automation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(automation)


def read(*args):
    return subprocess.check_output(list(args), text=True)


def audit(app, *, unsigned=False, revision=None, build=None, team=None, identity=None):
    app = Path(app).resolve(strict=True)
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert info['CFBundleName'] == info['CFBundleDisplayName'] == info['CFBundleExecutable'] == 'CopyStory'
    assert info['CFBundleShortVersionString'] == '1.0.0'
    assert re.fullmatch('[0-9]+', info['CFBundleVersion'])
    assert re.fullmatch('[0-9a-f]{40}', info['CopyStorySourceRevision'])
    assert info['CopyStorySourceDirty'] in ('clean', 'dirty')
    assert not any(k.startswith('SU') or any(x in k for x in ['Development', 'Engineering', 'NativeSourceOnly', 'Feasibility', 'Probe', 'DirectPasteTest']) for k in info)
    if revision:
        assert info['CopyStorySourceRevision'] == revision
    if build:
        assert info['CFBundleVersion'] == build
    exe = app/'Contents/MacOS/CopyStory'
    assert read('/usr/bin/lipo', '-archs', str(exe)).strip() == 'arm64'
    assert re.search(r'\bminos\s+26\.0\b', read('/usr/bin/otool', '-l', str(exe)))
    assert 'Sparkle' not in read('/usr/bin/otool', '-L', str(exe))
    assert info['LSMinimumSystemVersion'] == '26.0'
    assert info['LSApplicationCategoryType'] == 'public.app-category.utilities'
    assert info['CFBundleIconFile'] == 'CopyStory.icns'
    assert (app/'Contents/Resources/LICENSE').is_file()
    for name in ['CopyStory.icns', 'PrivacyInfo.xcprivacy']:
        assert (app/'Contents/Resources'/name).read_bytes() == (ROOT/'Resources'/name).read_bytes()
    checked = automation.verify(app)
    signature = subprocess.run(['/usr/bin/codesign', '-dvv', str(app)], capture_output=True, text=True, check=True).stderr
    entitlements = None
    if unsigned:
        assert 'Signature=adhoc' in signature and 'linker-signed' in signature
        assert 'Sealed Resources=none' in signature and not (app/'Contents/_CodeSignature').exists()
    else:
        assert all((team, identity, revision, build)), 'Signed audit requires exact team/certificate/revision/build'
        assert int(build) > 0 and info['CopyStorySourceDirty'] == 'clean'
        assert 'Authority=Apple Distribution:' in signature or 'Authority=3rd Party Mac Developer Application:' in signature
        assert 'TeamIdentifier='+team in signature and 'runtime' in signature
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        result = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True)
        entitlements = plistlib.loads(result.stdout)
        expected = {'com.apple.security.app-sandbox': True,
                    'com.apple.security.files.user-selected.read-only': True,
                    'com.apple.application-identifier': team+'.com.copystory.app',
                    'com.apple.developer.team-identifier': team}
        assert all(entitlements.get(k) == v for k, v in expected.items()), entitlements
        assert set(entitlements).issubset(set(expected) | {'beta-reports-active'}), entitlements
        if 'beta-reports-active' in entitlements:
            assert entitlements['beta-reports-active'] is True
        with tempfile.TemporaryDirectory(prefix='copystory-beta-public-cert-') as directory:
            prefix = str(Path(directory)/'certificate')
            subprocess.run(['/usr/bin/codesign', '-d', '--extract-certificates='+prefix, str(app)], check=True, capture_output=True)
            assert hashlib.sha1(Path(prefix+'0').read_bytes()).hexdigest().upper() == identity.upper()
        profile = app/'Contents/embedded.provisionprofile'
        data = subprocess.run(['/usr/bin/openssl', 'smime', '-verify', '-inform', 'der', '-noverify', '-in', str(profile)], capture_output=True, check=True).stdout
        profile_info = plistlib.loads(data)
        assert profile_info['ExpirationDate'].replace(tzinfo=timezone.utc) > datetime.now(timezone.utc)
        assert profile_info['Platform'] == ['OSX']
        assert profile_info['TeamIdentifier'] == [team]
        assert profile_info['Entitlements']['com.apple.application-identifier'] == team+'.com.copystory.app'
        assert not profile_info.get('ProvisionedDevices') and not profile_info.get('ProvisionsAllDevices')
        assert identity.upper() in [hashlib.sha1(c).hexdigest().upper() for c in profile_info['DeveloperCertificates']]
    return {'result': 'PASS', 'channel': 'Direct Paste TestFlight', 'signed': not unsigned,
            'metadata': info, 'entitlements': entitlements, 'checkedExecutables': checked,
            'executableSHA256': hashlib.sha256(exe.read_bytes()).hexdigest(),
            'nativeRuntime': 'NOT EXECUTED', 'AppStoreSubmission': False}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('app'); p.add_argument('--unsigned', action='store_true')
    for key in ['revision', 'build', 'team', 'identity']:
        p.add_argument('--'+key)
    a = p.parse_args()
    print(json.dumps(audit(a.app, unsigned=a.unsigned, revision=a.revision, build=a.build,
                           team=a.team, identity=a.identity), indent=2))
