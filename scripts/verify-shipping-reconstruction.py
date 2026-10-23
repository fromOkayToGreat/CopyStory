#!/usr/bin/env python3
"""Static package checks only; never runs the built app."""
from pathlib import Path
import subprocess,plistlib,json,hashlib,sys,re
app=Path(sys.argv[1]);exe=app/'Contents/MacOS/CopyStory'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.copystory.app'
assert info['CFBundleShortVersionString']=='1.0.0' and info['CFBundleVersion']=='0'
assert info['CopyStoryEngineeringOnly'] is True
assert not any(k.startswith('SU') or 'Feasibility' in k for k in info)
assert (app/'Contents/Resources/LICENSE').is_file()
def read(*args):return subprocess.check_output(list(args),text=True)
arch=read('/usr/bin/lipo','-archs',str(exe)).strip();assert arch=='arm64'
loads=read('/usr/bin/otool','-l',str(exe));assert re.search(r'\bminos\s+26\.0\b',loads)
links=read('/usr/bin/otool','-L',str(exe));assert 'Sparkle' not in links
symbols=read('/usr/bin/nm','-u',str(exe))
for forbidden in ['_AXUIElement','_AXIsProcessTrustedWithOptions']:
 assert forbidden not in symbols,forbidden+' unexpectedly linked'
nativeSymbols=[name for name in ['_CGEventPostToPid','_CGPreflightPostEventAccess','_CGRequestPostEventAccess'] if name in symbols]
assert re.search(r'(?m)\b_CGEventPost\s*$',symbols) is None,'Global event posting unexpectedly linked'
gates=None
if info.get('CopyStoryNativeSourceOnly'):
 gates=json.loads(read(sys.executable,str(Path(__file__).resolve().with_name('verify-native-source-gates.py'))))
 assert gates['result']=='PASS'
else:
 assert not nativeSymbols,'Native API symbols require source-only marker and verified hard gates'
result={'nativeAPISymbolsLinked':nativeSymbols,'nativeSourceBarriers':gates,'kind':'unsigned compile-only engineering archive, NOT a release candidate','architecture':arch,'minimumOS':'26.0','automaticEventDelivery':'hard source gates disabled; linked API symbols inventoried, not runtime acceptance','launch':'compile-time refused; never executed','info':info,'linkedLibraries':links,'loadCommands':loads,'bundleFilesSHA256':{str(p.relative_to(app)):hashlib.sha256(p.read_bytes()).hexdigest() for p in app.rglob('*') if p.is_file()},'effectiveSandbox':'NOT runtime/signature verified; sandbox-only entitlement is a build input; signing disabled'}
print(json.dumps(result,indent=2))
