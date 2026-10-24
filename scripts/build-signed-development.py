#!/usr/bin/env python3
"""Plan by default. --execute-signing uses a private key and needs separate approval.

Never installs, launches, provisions, logs in, requests permissions or accesses data.
Use only an approved Apple Development identity, specified by public SHA-1.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def plan(args, developer_dir):
    output = args.output.expanduser().absolute()
    if output.exists() or output.is_symlink() or output.resolve().is_relative_to(ROOT):
        raise ValueError('Use a fresh output path outside this source worktree')
    if not Path(developer_dir, 'usr/bin/xcodebuild').is_file():
        raise ValueError('DEVELOPER_DIR must name the full Xcode Developer directory')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT, text=True))
    command = [str(Path(developer_dir)/'usr/bin/xcodebuild'), '-project', 'CopyStoryShipping.xcodeproj',
        '-target', 'CopyStory', '-configuration', 'Debug', '-xcconfig', 'Config/DevelopmentSigned.xcconfig',
        'SYMROOT='+str(output/'Products'), 'OBJROOT='+str(output/'Intermediates'),
        'CLANG_MODULE_CACHE_PATH='+str(output/'ModuleCache'),
        'CLANG_MODULES_BUILD_SESSION_FILE='+str(output/'ModuleCache/Session.modulevalidation'),
        'COPYSTORY_SOURCE_REVISION='+revision, 'COPYSTORY_SOURCE_DIRTY=clean',
        'COPYSTORY_DEVELOPMENT_TEAM='+args.team,
        'COPYSTORY_DEVELOPMENT_IDENTITY='+args.identity.upper(),
        'COPYSTORY_DEVELOPMENT_BUILD_NUMBER='+args.build, 'build']
    return {'sourceRevision': revision, 'sourceDirty': dirty, 'output': str(output),
        'team': args.team, 'identitySHA1': args.identity.upper(), 'build': args.build,
        'mode': 'execute-signing' if args.execute_signing else 'plan-only',
        'initialSignedBaseline': args.initial_signed_baseline,
        'previous': str(args.previous.resolve(strict=True)) if args.previous else None,
        'command': command, 'runtimeAcceptance': 'UNRUN'}


def require_development_identity(identity):
    # Public metadata only; validate type before any Xcode/private-key operation.
    identities = subprocess.check_output(
        ['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    selected = re.findall(r'^\s*\d+\) ([0-9A-Fa-f]{40}) "([^"]+)"', identities, re.M)
    if not any(sha.upper() == identity.upper() and name.startswith('Apple Development: ')
               for sha, name in selected):
        raise ValueError('Selected certificate is not a locally valid Apple Development identity')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--team', required=True)
    parser.add_argument('--identity', required=True, help='approved Apple Development public certificate SHA-1')
    parser.add_argument('--build', required=True, help='allocated development build integer >=2; never an App Store allocation')
    parser.add_argument('--output', required=True, type=Path)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--previous', type=Path, help='last accepted signed bundle for two-way continuity checks')
    group.add_argument('--initial-signed-baseline', action='store_true', help='explicit first ad-hoc to certificate transition; requires migration approval')
    parser.add_argument('--execute-signing', action='store_true', help='PRIVATE KEY USE: requires separate approval; default prints a plan only')
    args = parser.parse_args()
    for name, pattern in [('team', '[A-Z0-9]{10}'), ('identity', '[0-9a-fA-F]{40}'), ('build', '[1-9][0-9]*')]:
        if not re.fullmatch(pattern, getattr(args, name)):
            parser.error('Invalid '+name)
    if int(args.build) < 2:
        parser.error('Build1 is the historical baseline; allocate build2 or later')
    try:
        developer_dir = os.environ.get('DEVELOPER_DIR', '')
        if not developer_dir:
            raise ValueError('Set DEVELOPER_DIR explicitly; global toolchain selection is never changed')
        receipt = plan(args, developer_dir)
        if not args.execute_signing:
            print(json.dumps(receipt, indent=2))
            return 0
        if receipt['sourceDirty']:
            raise ValueError('Commit reviewed implementation before signing: source worktree is dirty')
        require_development_identity(args.identity)
        if args.previous:
            previous_info = plistlib.loads((args.previous/'Contents/Info.plist').read_bytes())
            previous_build = previous_info.get('CFBundleVersion', '')
            if not re.fullmatch('[1-9][0-9]*', previous_build) or int(args.build) <= int(previous_build):
                raise ValueError('Build must increase over previous accepted bundle')
            subprocess.run([sys.executable, str(ROOT/'scripts/verify-development.py'), str(args.previous),
                '--signed', '--expected-team', args.team,
                '--expected-identity', args.identity, '--expected-build', previous_build,
                '--expected-revision', previous_info['CopyStorySourceRevision']], check=True, stdout=subprocess.DEVNULL)
        output = Path(receipt['output'])
        output.mkdir(parents=True, exist_ok=False)
        (output/'ModuleCache').mkdir()
        (output/'ModuleCache/Session.modulevalidation').touch()
        (output/'build-plan.json').write_text(json.dumps(receipt, indent=2)+'\n')
        with (output/'build.log').open('w') as log:
            subprocess.run(receipt['command'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        after_revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        after_dirty = subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT, text=True)
        if after_revision != receipt['sourceRevision'] or after_dirty:
            raise ValueError('Source changed during build; artifact is not accepted')
        app = output/'Products/Debug/CopyStory Development.app'
        verify = [sys.executable, str(ROOT/'scripts/verify-development.py'), str(app), '--signed',
            '--expected-team', args.team, '--expected-identity', args.identity,
            '--expected-revision', receipt['sourceRevision'], '--expected-build', args.build]
        if args.previous:
            verify += ['--previous', str(args.previous)]
        with (output/'verification.json').open('w') as log:
            subprocess.run(verify, check=True, stdout=log)
        with (output/'source.tar').open('wb') as archive:
            subprocess.run(['git', 'archive', receipt['sourceRevision']], cwd=ROOT, stdout=archive, check=True)
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app), str(output/'candidate.zip')], check=True)
        roundtrip = output/'roundtrip'
        roundtrip.mkdir()
        subprocess.run(['/usr/bin/ditto', '-x', '-k', str(output/'candidate.zip'), str(roundtrip)], check=True)
        copied = subprocess.check_output([*verify[:2], str(roundtrip/app.name), *verify[3:]], text=True)
        original = json.loads((output/'verification.json').read_text())
        if json.loads(copied)['inventory'] != original['inventory']:
            raise ValueError('ZIP roundtrip changed bundle inventory')
        (output/'roundtrip-verification.json').write_text(copied)
        for name, command in [('xcode-version.txt', [receipt['command'][0], '-version']),
                              ('sdk-version.txt', ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-version']),
                              ('host-version.txt', ['/usr/bin/sw_vers'])]:
            (output/name).write_text(subprocess.check_output(command, text=True))
        (output/'build-settings.txt').write_text(subprocess.check_output(
            [*receipt['command'][:-1], '-showBuildSettings'], cwd=ROOT, text=True))
        digests = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in output.iterdir() if p.is_file()}
        (output/'SHA256.json').write_text(json.dumps(digests, indent=2)+'\n')
        print(str(app))
        return 0
    except (OSError, ValueError, TypeError, KeyError, subprocess.CalledProcessError) as error:
        print('Stopped; keep any partial evidence, do not install: '+str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
