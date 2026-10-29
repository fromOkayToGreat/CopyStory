#!/usr/bin/env python3
"""Static unsigned production package/source checks. Never executes the app."""
from pathlib import Path
import hashlib, json, plistlib, re, subprocess, sys
root = Path(__file__).resolve().parent.parent
native = (root / 'Sources/CopyStory/NativePasteAdapter.swift').read_text()
production = native.split('#elseif COPYSTORY_PRODUCTION\n', 1)[1].split('#else', 1)[0]
for gate in ['appLaunchEnabled', 'storageEnabled', 'clipboardEnabled', 'observationEnabled',
             'shortcutEnabled', 'loginEnabled', 'postingConsentEnabled', 'realPostingEnabled']:
    assert f'static let {gate} = true' in production, gate
# Keep the reconstruction assertions independent and closed.
subprocess.run([sys.executable, str(root / 'scripts/verify-native-source-gates.py')], check=True, stdout=subprocess.DEVNULL)
entry = (root / 'Sources/CopyStory/CopyStoryMain.swift').read_text()
assert '#if COPYSTORY_DEVELOPMENT || COPYSTORY_PRODUCTION' in entry
assert entry.index('try UpdateService.verifyPackagedRuntime()') < entry.index('NSApplication.shared')
assert '#if APP_STORE && !COPYSTORY_DEVELOPMENT && !COPYSTORY_PRODUCTION' in entry
config = (root / 'Config/Production.xcconfig').read_text()
assert 'SWIFT_ACTIVE_COMPILATION_CONDITIONS = APP_STORE COPYSTORY_PRODUCTION\n' in config
app = Path(sys.argv[1]); exe = app / 'Contents/MacOS/CopyStory'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.copystory.app'
assert info['CFBundleName'] == info['CFBundleDisplayName'] == 'CopyStory'
assert info['CFBundleShortVersionString'] == '1.0.0' and info['CFBundleVersion'] == '0'
assert info['CopyStoryProductionBuild'] is True and info['CopyStoryBuildConfiguration'] == 'Production'
assert re.fullmatch('[0-9a-f]{40}', info['CopyStorySourceRevision'])
assert info['CopyStorySourceDirty'] in ['clean', 'dirty']
assert not any(k.startswith('SU') or any(x in k for x in ['Development', 'Engineering', 'NativeSourceOnly', 'Feasibility', 'Probe']) for k in info)
assert (app / 'Contents/Resources/LICENSE').is_file()
assert info['LSApplicationCategoryType'] == 'public.app-category.utilities'
assert info['CFBundleIconFile'] == 'CopyStory.icns'
resources = app / 'Contents/Resources'
iconSHA256 = hashlib.sha256((resources / 'CopyStory.icns').read_bytes()).hexdigest()
assert iconSHA256 == 'bb3bac3fd1d5e624cd7bda3c32415b3f5312ffbff1ed743b536afc3c2a75d58c'
expectedPrivacy = {'NSPrivacyAccessedAPITypes': [
    {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategory' + category,
     'NSPrivacyAccessedAPITypeReasons': [reason]} for category, reason in
    [('UserDefaults', 'CA92.1'), ('SystemBootTime', '35F9.1'), ('FileTimestamp', 'C617.1')]]}
privacy = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
assert privacy == expectedPrivacy
for name in ['CopyStory.icns', 'PrivacyInfo.xcprivacy']:
    assert (resources / name).read_bytes() == (root / 'Resources' / name).read_bytes()

assert plistlib.loads((root / 'Config/AppStore.entitlements').read_bytes()) == {'com.apple.security.app-sandbox': True,
    'com.apple.security.files.user-selected.read-only': True}
def read(*args): return subprocess.check_output(list(args), text=True)
assert read('/usr/bin/lipo', '-archs', str(exe)).strip() == 'arm64'
loads = read('/usr/bin/otool', '-l', str(exe))
assert re.search(r'\bminos\s+26\.0\b', loads)
# arm64 ld emits an unsealed linker signature even with Xcode signing disabled.
# It supplies no identity, entitlements or sealed bundle resources.
signature = subprocess.run(['/usr/bin/codesign', '-dvv', str(app)], capture_output=True, text=True)
assert signature.returncode == 0
assert 'Signature=adhoc' in signature.stderr and 'linker-signed' in signature.stderr
assert 'TeamIdentifier=not set' in signature.stderr and 'Sealed Resources=none' in signature.stderr
assert not (app / 'Contents/_CodeSignature').exists()
links = read('/usr/bin/otool', '-L', str(exe)); assert 'Sparkle' not in links
symbols = read('/usr/bin/nm', '-u', str(exe))
for forbidden in ['_AXUIElement', '_AXIsProcessTrusted']:
    assert forbidden not in symbols, forbidden
assert all(s in symbols for s in ['_CGEventPostToPid', '_CGPreflightPostEventAccess', '_CGRequestPostEventAccess'])
assert re.search(r'(?m)\b_CGEventPost\s*$', symbols) is None
strings = read('/usr/bin/strings', str(exe))
for diagnostic in ['historyPresentation', 'canonicalDevelopmentPath', 'Next normal refresh', 'Check readiness']:
    assert diagnostic not in strings, diagnostic
print(json.dumps({'result': 'PASS', 'kind': 'unsigned production preparation; build0 unallocated',
    'iconSHA256': iconSHA256, 'privacyManifest': privacy,
    'info': info, 'architecture': 'arm64', 'minimumOS': '26.0',
    'signature': 'arm64 linker-only adhoc; no signing step, team, entitlements or sealed resources; sandbox is build input only',
    'diagnostics': 'no AX trust symbols, presentation logging category or readiness UI strings',
    'executableSHA256': hashlib.sha256(exe.read_bytes()).hexdigest(),
    'runtimeAcceptance': 'UNRUN; app never executed'}, indent=2))
