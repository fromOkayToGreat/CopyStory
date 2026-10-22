#!/usr/bin/env python3
"""Static candidate checks only; never execute the built app."""
import hashlib, json, plistlib, re, subprocess, sys
from pathlib import Path
app=Path(sys.argv[1]); info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.copystory.development'
assert info['CopyStoryDevelopmentBuild'] is True
assert re.fullmatch('[0-9a-f]{40}',info['CopyStorySourceRevision'])
assert info['CopyStorySourceDirty'] in ('clean','dirty')
assert info['CopyStoryBuildConfiguration']=='Debug'
assert info['CFBundleShortVersionString']=='1.0.0' and info['CFBundleVersion']=='1'
assert info['LSMinimumSystemVersion']=='26.0'
assert not any(k.startswith('SU') for k in info)
assert all(k not in info for k in ('CopyStoryNativeSourceOnly','CopyStoryEngineeringOnly','CopyStorySandboxFeasibility'))
exe=app/'Contents/MacOS'/info['CFBundleExecutable']
archs=subprocess.check_output(['lipo','-archs',str(exe)],text=True).strip()
assert archs=='arm64'
links=subprocess.check_output(['otool','-L',str(exe)],text=True)
assert 'Sparkle' not in links
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
ent=subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL)
assert plistlib.loads(ent)=={'com.apple.security.app-sandbox':True}
print(json.dumps({'info':info,'architectures':archs,'executableSHA256':hashlib.sha256(exe.read_bytes()).hexdigest(),'staticVerification':'PASS','runtimeAcceptance':'UNRUN','signature':'local ad-hoc sandbox; not distribution signed'},indent=2))
