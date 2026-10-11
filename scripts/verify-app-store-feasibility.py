#!/usr/bin/env python3
"""Verify the narrow feasibility bundle boundary, not App Store acceptance."""
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
def require(value, message):
    if not value:
        raise SystemExit(message)

p = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
require(p.get('CFBundleIdentifier') == 'com.copystory.sandbox-feasibility', 'Wrong probe identity')
require(p.get('CopyStorySandboxFeasibility') is True, 'Missing feasibility marker')
require(not any(k.startswith('SU') for k in p), 'Sparkle configuration remains')
require(not (app / 'Contents/Frameworks').exists(), 'Unexpected embedded framework')
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)], check=True)
entitlements = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL)
require(plistlib.loads(entitlements) == {'com.apple.security.app-sandbox': True}, 'Unexpected or missing entitlement')
exe = app / 'Contents/MacOS/CopyStory'
require(set(subprocess.check_output(['lipo', '-archs', str(exe)], text=True).split()) == {'arm64', 'x86_64'}, 'Expected both supported architectures')
linked = subprocess.check_output(['otool', '-L', str(exe)], text=True)
require('Sparkle' not in linked, 'Sparkle remains linked')
print('Feasibility package verified: sandbox only, isolated identity, universal, no Sparkle.')
