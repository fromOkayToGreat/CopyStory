#!/usr/bin/env python3
"""Inspect a bundle without running it. PASS is static, never runtime acceptance.

Default mode accepts the historical ad-hoc development candidate. --signed
requires explicit expected team/revision/build/certificate and Apple Development.
No keychain, permission API, clipboard or user-store access. Public leaf certificate
extraction, when requested, uses a temporary directory removed after inspection.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile


def run(args):
    result = subprocess.run(args, capture_output=True, text=True)
    return {'exit': result.returncode, 'stdout': result.stdout.strip(),
            'stderr': result.stderr.strip()}


def requirement(app):
    result = run(['/usr/bin/codesign', '-d', '-r-', str(app)])
    match = re.search(r'^(?:# )?designated => (.+)$',
                      result['stdout']+'\n'+result['stderr'], re.M)
    if result['exit'] or not match:
        raise ValueError('Cannot read designated requirement')
    return match.group(1)


def inventory(app):
    """Freeze files, directories, modes and internal symlinks; never follow them."""
    app = app.resolve(strict=True)
    entries = []
    for path in sorted([app, *app.rglob('*')]):
        mode = path.lstat().st_mode
        entry = {'path': str(path.relative_to(app)), 'mode': oct(stat.S_IMODE(mode))}
        if path.is_symlink():
            target = path.readlink()
            if target.is_absolute() or not path.resolve().is_relative_to(app):
                raise ValueError('External bundle symlink')
            entry.update(type='symlink', target=str(target))
        elif stat.S_ISREG(mode):
            entry.update(type='file', size=path.stat().st_size,
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        elif stat.S_ISDIR(mode):
            entry.update(type='directory')
        else:
            raise ValueError('Unsupported bundle file type')
        entries.append(entry)
    return entries


def audit(app, *, signed=False, team=None, revision=None, build=None, identity=None,
          previous=None):
    app = app.resolve(strict=True)
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    exe_name = info['CFBundleExecutable']
    if not isinstance(exe_name, str) or Path(exe_name).name != exe_name:
        raise ValueError('Invalid executable name')
    exe = app/'Contents/MacOS'/exe_name
    signature = run(['/usr/bin/codesign', '-d', '--verbose=4', str(app)])
    signature_text = signature['stdout']+'\n'+signature['stderr']
    authorities = re.findall(r'^Authority=(.+)$', signature_text, re.M)
    actual_team = re.findall(r'^TeamIdentifier=(.+)$', signature_text, re.M)
    ent_result = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)],
                                capture_output=True)
    ent = plistlib.loads(ent_result.stdout) if ent_result.returncode == 0 else None
    dr = requirement(app)
    checks = {
        'bundleID': info.get('CFBundleIdentifier') == 'com.copystory.development',
        'development': info.get('CopyStoryDevelopmentBuild') is True,
        'sourceState': info.get('CopyStorySourceDirty') in ('clean', 'dirty'),
        'revision': bool(re.fullmatch('[0-9a-f]{40}', info.get('CopyStorySourceRevision', ''))),
        'debug': info.get('CopyStoryBuildConfiguration') == 'Debug',
        'marketingVersion': info.get('CFBundleShortVersionString') == '1.0.0',
        'build': bool(re.fullmatch('[1-9][0-9]*', info.get('CFBundleVersion', ''))),
        'minimumOS': info.get('LSMinimumSystemVersion') == '26.0',
        'arm64': run(['/usr/bin/lipo', '-archs', str(exe)]) ==
                 {'exit': 0, 'stdout': 'arm64', 'stderr': ''},
        'signatureMetadata': signature['exit'] == 0,
        'strictSignature': run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)])['exit'] == 0,
        'hardenedRuntime': bool(re.search(r'^CodeDirectory .*flags=.*\bruntime\b', signature_text, re.M)),
        'sandboxOnly': ent == {'com.apple.security.app-sandbox': True},
        'noUpdaterKeys': not any(k.startswith('SU') for k in info),
        'noFixtureMarkers': all(k not in info for k in
            ('CopyStoryNativeSourceOnly', 'CopyStoryEngineeringOnly', 'CopyStorySandboxFeasibility')),
    }
    links = run(['/usr/bin/otool', '-L', str(exe)])
    checks['noSparkle'] = links['exit'] == 0 and 'Sparkle' not in links['stdout']
    leaf_sha1 = None
    if identity:
        with tempfile.TemporaryDirectory(prefix='copystory-public-cert-') as directory:
            prefix = str(Path(directory)/'certificate')
            extracted = run(['/usr/bin/codesign', '-d', '--extract-certificates', prefix, str(app)])
            leaf = Path(prefix+'0')
            if extracted['exit'] == 0 and leaf.is_file():
                leaf_sha1 = hashlib.sha1(leaf.read_bytes()).hexdigest().upper()
        checks['exactCertificate'] = leaf_sha1 == identity.upper()
    if team:
        checks['team'] = actual_team == [team]
    if signed:
        checks['cleanSource'] = info.get('CopyStorySourceDirty') == 'clean'
        checks['appleDevelopment'] = bool(authorities and authorities[0].startswith('Apple Development: '))
        checks['certificateBacked'] = 'Signature=adhoc' not in signature_text
        checks['stableRequirement'] = not dr.startswith('cdhash ')
    if revision:
        checks['expectedRevision'] = info.get('CopyStorySourceRevision') == revision
    if build:
        checks['expectedBuild'] = info.get('CFBundleVersion') == build
    if previous:
        previous = previous.resolve(strict=True)
        previous_info = plistlib.loads((previous/'Contents/Info.plist').read_bytes())
        checks['previousBundleID'] = previous_info.get('CFBundleIdentifier') == info.get('CFBundleIdentifier')
        previous_build = previous_info.get('CFBundleVersion', '')
        current_build = info.get('CFBundleVersion', '')
        checks['buildIncreases'] = (bool(re.fullmatch('[1-9][0-9]*', previous_build)) and
            bool(re.fullmatch('[1-9][0-9]*', current_build)) and int(current_build) > int(previous_build))
        checks['candidateSatisfiesPrevious'] = run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', '='+requirement(previous), str(app)])['exit'] == 0
        checks['previousSatisfiesCandidate'] = run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', '='+dr, str(previous)])['exit'] == 0
    keys = ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion',
            'CopyStorySourceRevision', 'CopyStorySourceDirty', 'CopyStoryBuildConfiguration',
            'LSMinimumSystemVersion')
    return {'app': str(app), 'metadata': {k: info.get(k) for k in keys},
            'executableSHA256': hashlib.sha256(exe.read_bytes()).hexdigest(),
            'designatedRequirement': dr, 'team': actual_team, 'authorities': authorities,
            'leafCertificateSHA1': leaf_sha1, 'entitlements': ent,
            'inventory': inventory(app), 'checks': checks,
            'staticVerdict': 'PASS' if all(checks.values()) else 'FAIL',
            'runtimeAcceptance': 'UNRUN',
            'signature': 'Apple Development required' if signed else 'static only; signing channel not constrained',
            'signingContinuityGateRequested': bool(signed and previous)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--signed', action='store_true')
    parser.add_argument('--expected-team')
    parser.add_argument('--expected-revision')
    parser.add_argument('--expected-build')
    parser.add_argument('--expected-identity', help='public leaf certificate SHA-1, not a private key')
    parser.add_argument('--previous', type=Path, help='last accepted same-channel bundle; requires increasing build')
    args = parser.parse_args()
    if args.signed and not all((args.expected_team, args.expected_revision,
                                args.expected_build, args.expected_identity)):
        parser.error('--signed needs --expected-team/revision/build/identity')
    for name, pattern in [('expected_team', '[A-Z0-9]{10}'), ('expected_revision', '[0-9a-f]{40}'),
                          ('expected_build', '[1-9][0-9]*'), ('expected_identity', '[0-9a-fA-F]{40}')]:
        value = getattr(args, name)
        if value is not None and not re.fullmatch(pattern, value):
            parser.error('Invalid '+name)
    try:
        receipt = audit(args.app, signed=args.signed, team=args.expected_team,
                        revision=args.expected_revision, build=args.expected_build,
                        identity=args.expected_identity, previous=args.previous)
        print(json.dumps(receipt, indent=2))
        return 0 if receipt['staticVerdict'] == 'PASS' else 1
    except (OSError, ValueError, TypeError, KeyError, plistlib.InvalidFileException) as error:
        print(json.dumps({'staticVerdict': 'ERROR', 'reason': str(error)}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
