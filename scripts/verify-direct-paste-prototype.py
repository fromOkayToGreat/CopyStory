#!/usr/bin/env python3
"""Read-only artifact verifier. Never launches, prompts, installs or posts."""
import hashlib,json,pathlib,plistlib,subprocess,sys
root=pathlib.Path(sys.argv[1]).resolve()
manifest=json.loads((root/'source-manifest.json').read_text())
artifacts=[]
for name,bundle in [('CS Paste Probe','com.copystory.paste-probe.fro22'),
                    ('CS Paste Target','com.copystory.paste-fixture.target'),
                    ('CS Paste Decoy','com.copystory.paste-fixture.decoy')]:
    app=root/(name+'.app'); p=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert p['CFBundleIdentifier']==bundle and p['CopyStoryDirectPasteExperiment'] is True
    assert p['LSMinimumSystemVersion']=='26.0' and not any(k.startswith('SU') for k in p)
    exe=app/'Contents/MacOS'/p['CFBundleExecutable']
    assert subprocess.check_output(['lipo','-archs',str(exe)],text=True).strip()=='arm64'
    assert 'Sparkle' not in subprocess.check_output(['otool','-L',str(exe)],text=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    ent=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
    assert ent=={'com.apple.security.app-sandbox':True},ent
    signature=subprocess.check_output(['codesign','-dv','--verbose=4',str(app)],stderr=subprocess.STDOUT,text=True)
    artifacts.append({'bundle':bundle,'executableSHA256':hashlib.sha256(exe.read_bytes()).hexdigest(),
                      'entitlements':ent,'signature':signature,'strictVerification':'passed'})
manifest['artifacts']=artifacts
(root/'verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('All three separate arm64 sandbox experiment bundles verified.')
