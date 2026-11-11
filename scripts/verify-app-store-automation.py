#!/usr/bin/env python3
"""Reject automation APIs in every Mach-O in an App Store bundle. Never launches it."""
from pathlib import Path
import re
import subprocess
import sys

FORBIDDEN = re.compile(r'_(?:AX(?:UIElement|Observer|IsProcessTrusted)|CG(?:Request|Preflight)(?:PostEvent|ListenEvent)Access|CGEvent(?:Post|Tap|CreateKeyboardEvent|CreateMouseEvent|CreateScrollWheelEvent)|CGPost(?:Keyboard|Mouse|ScrollWheel)Event)')

def verify(app):
    checked = []
    for path in sorted(Path(app).rglob('*')):
        if not path.is_file():
            continue
        kind = subprocess.check_output(['/usr/bin/file', '-b', str(path)], text=True)
        if 'Mach-O' not in kind:
            continue
        # Undefined imports survive stripping. Check all architectures and nested code.
        symbols = subprocess.check_output(['/usr/bin/nm', '-u', str(path)], text=True)
        if match := FORBIDDEN.search(symbols):
            raise ValueError(f'Forbidden App Store automation API {match.group()} in {path.name}')
        checked.append(str(path.relative_to(app)))
    if not checked:
        raise ValueError('No Mach-O binaries found')
    return checked

if __name__ == '__main__':
    print('PASS: no Accessibility automation, event posting/taps or permission APIs:', ', '.join(verify(Path(sys.argv[1]))))
