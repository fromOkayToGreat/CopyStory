#!/usr/bin/env python3
"""Audit the explicitly selected Direct Paste beta without executing it."""
from pathlib import Path
import json
import plistlib
import re
import subprocess
import sys

REQUIRED = {'_CGPreflightPostEventAccess', '_CGRequestPostEventAccess',
            '_CGEventCreateKeyboardEvent', '_CGEventPostToPid'}
FORBIDDEN = re.compile(r'_(?:AX(?:UIElement\w*|Observer\w*|IsProcessTrusted\w*)|CG(?:Request|Preflight)ListenEventAccess|CGEvent(?:Tap\w*|Post|PostToPSN|CreateMouseEvent|CreateScrollWheelEvent)|CGPost(?:Keyboard|Mouse|ScrollWheel)Event)(?=\s|$)', re.M)


def verify(app):
    app = Path(app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if not (info.get('CFBundleIdentifier') == 'com.copystory.app' and
            info.get('CopyStoryBuildConfiguration') == 'TestFlight' and
            info.get('CopyStoryTestFlightBuild') is True and
            info.get('CopyStoryProductionBuild') is True):
        raise ValueError('Requires the explicit TestFlight package, not copy-only Production or development')
    checked = []
    for path in sorted(app.rglob('*')):
        if not path.is_file():
            continue
        kind = subprocess.check_output(['/usr/bin/file', '-b', str(path)], text=True)
        if 'Mach-O' not in kind:
            continue
        relative = str(path.relative_to(app))
        if relative != 'Contents/MacOS/CopyStory':
            raise ValueError('Unexpected nested executable: ' + relative)
        symbols = subprocess.check_output(['/usr/bin/nm', '-u', str(path)], text=True)
        if match := FORBIDDEN.search(symbols):
            raise ValueError('Unapproved beta automation API: ' + match.group())
        imports = set(re.findall(r'(_\w+)\s*$', symbols, re.M))
        if not REQUIRED.issubset(imports):
            raise ValueError('Direct Paste APIs absent: ' + str(sorted(REQUIRED - imports)))
        checked.append(relative)
    if checked != ['Contents/MacOS/CopyStory']:
        raise ValueError('Expected one self-contained app executable')
    return checked


if __name__ == '__main__':
    print(json.dumps({'result': 'PASS', 'channel': 'Direct Paste TestFlight beta',
                      'executables': verify(sys.argv[1]), 'AppStoreApproval': False}))
