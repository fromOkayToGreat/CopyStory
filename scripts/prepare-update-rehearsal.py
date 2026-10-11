#!/usr/bin/env python3
"""Create isolated, auditable A/B source snapshots; never install or publish."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PRODUCTION_REPO = 'fromOkayToGreat/CopyStory'
BUNDLE = 'com.copystory.rehearsal'
ACCOUNT = BUNDLE + '.sparkle'


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise ValueError(f'Source changed; review rehearsal transformation: {path.name}')
    path.write_text(text.replace(old, new))


def prepare(destination, repository, public_key, root=ROOT):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*', repository):
        raise ValueError('Expected GitHub OWNER/REPOSITORY')
    if repository.lower() == PRODUCTION_REPO.lower():
        raise ValueError('Use a separate disposable repository')
    original = plistlib.loads((root / 'Config/Info.plist').read_bytes())
    decoded = base64.b64decode(public_key, validate=True)
    if len(decoded) != 32 or decoded == base64.b64decode(original['SUPublicEDKey']):
        raise ValueError('Use a separate 32-byte Sparkle public key')
    destination = Path(destination).resolve()
    # Keep generated source and later credentials/artifacts under ignored .build.
    workspace = (root / '.build/update-rehearsals').resolve()
    if not destination.is_relative_to(workspace) or destination == workspace:
        raise ValueError('Destination must be a new directory beneath .build/update-rehearsals/')
    files = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard', '-z']).decode().split('\0')
    files = [name for name in files if name and not name.startswith('.github/')]
    for name in files:
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Unsupported source entry: {name}')
    destination.mkdir(parents=True, exist_ok=False)
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files}
    feed = f'https://github.com/{repository}/releases/download/rehearsal-feed/appcast.xml'
    for label, version, build in [('A', '0.0.1', '1'), ('B', '0.0.2', '2')]:
        target = destination / label
        for name in files:
            out = target / name
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(root / name, out)
        p = dict(original)
        p.update(CFBundleIdentifier=BUNDLE, CFBundleName='CopyStory Rehearsal',
                 CFBundleDisplayName='CopyStory Rehearsal', CFBundleVersion=build,
                 CFBundleShortVersionString=version, SUFeedURL=feed,
                 SUPublicEDKey=public_key, CopyStoryUpdateRehearsal=True)
        (target / 'Config/Info.plist').write_bytes(plistlib.dumps(p))
        service = target / 'Sources/CopyStory/UpdateService.swift'
        replace_once(service, '"com.copystory.app"', json.dumps(BUNDLE))
        replace_once(service, f'https://github.com/{PRODUCTION_REPO}/releases/latest/download/appcast.xml', feed)
        owner, repo = repository.split('/')
        replace_once(service, 'parts[1] == "fromOkayToGreat", parts[2] == "CopyStory"',
                     f'parts[1] == "{owner}", parts[2] == "{repo}"')
        app = target / 'Sources/CopyStory/CopyStoryApp.swift'
        replace_once(app, 'appendingPathComponent("CopyStory", isDirectory: true)',
                     'appendingPathComponent("CopyStory Rehearsal", isDirectory: true)')
        policy = target / 'scripts/release_policy.py'
        replace_once(policy, f'REPOSITORY = "{PRODUCTION_REPO}"', f'REPOSITORY = "{repository}"')
        replace_once(policy, '/releases/latest/download/appcast.xml', '/releases/download/rehearsal-feed/appcast.xml')
        replace_once(policy, '"com.copystory.app"', json.dumps(BUNDLE))
        replace_once(policy, 'require(not p.get("CopyStoryUpdateRehearsal"), "Rehearsal builds cannot enter the production pipeline")',
                     'require(p.get("CopyStoryUpdateRehearsal") is True, "Expected isolated rehearsal build")')
        release = target / 'scripts/release.sh'
        replace_once(release, 'python3 scripts/check-release-history.py "$@"',
                     '# Isolated fixed A/B versions; never query or publish stable release history.')
        release.write_text(release.read_text().replace(PRODUCTION_REPO, repository).replace('com.copystory.app.sparkle', ACCOUNT))
        # No upload/install helpers in the generated workspace can promote a test app.
        for name in ('publish-release.sh', 'install.sh'):
            (target / 'scripts' / name).write_text('#!/bin/bash\necho "Disabled in update rehearsal; follow docs/UPDATE_REHEARSAL.md." >&2\nexit 1\n')
        # Give the unchanged manifest/clean-source checks a local snapshot identity.
        subprocess.run(['git', 'init', '-q', str(target)], check=True)
        subprocess.run(['git', '-C', str(target), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(target), '-c', 'user.name=CopyStory Rehearsal',
                        '-c', 'user.email=rehearsal@example.invalid', '-c', 'commit.gpgsign=false',
                        'commit', '-qm', f'Isolated rehearsal {label}'], check=True)
    (destination / 'source-manifest.json').write_text(json.dumps({
        'sourceCommit': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
        'sourceFiles': hashes, 'repository': repository, 'feed': feed, 'keychainAccount': ACCOUNT,
        'bundleIdentifier': BUNDLE, 'status': 'Prepared only; signed A-to-B acceptance NOT RUN'
    }, indent=2) + '\n')
    (destination / 'RESULTS.md').write_text('# Update rehearsal evidence\n\nStatus: NOT RUN\n\n'
        'Record OS/hardware, source manifest, A/B hashes, notarization IDs, observed results and recovery.\n\n'
        '| Case | Expected | Actual / evidence |\n|---|---|---|\n'
        '| A to B | Version 2; synthetic data/settings preserved | NOT RUN |\n'
        '| Modified/unsigned feed | No installation | NOT RUN |\n'
        '| Corrupted/truncated/wrong-key archive | No installation | NOT RUN |\n'
        '| Equal/older build | No downgrade | NOT RUN |\n'
        '| Network interruption/unavailable feed | A usable; retry succeeds | NOT RUN |\n'
        '| Low disk/replacement interruption/relaunch failure | Recoverable app and history | NOT RUN |\n'
        '| Consent and network privacy | Opt-in respected; no clipboard payload | NOT RUN |\n')
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True, help='Disposable public GitHub OWNER/REPO (not production)')
    parser.add_argument('--public-key', required=True, help='Public key from the rehearsal Keychain account')
    parser.add_argument('--name', default='run-1')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', args.name):
        parser.error('Use a simple run name')
    print(prepare(ROOT / '.build/update-rehearsals' / args.name, args.repository, args.public_key))
