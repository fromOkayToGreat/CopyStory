#!/usr/bin/env python3
"""Compile/package only: no Xcode application task, registration, signing or launch.

Output must be a new .noindex directory. The manually assembled engineering
xcarchive is compressed and staging removed; it is not an App Store export.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse,hashlib,io,json,os,plistlib,shutil,subprocess,tarfile
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
root=Path(__file__).resolve().parent.parent;out=args.output.resolve()
assert out.name.endswith('.noindex'),'Output must end in .noindex'
assert not out.exists(),'Output must be new'
def git(*args):return subprocess.check_output(['git','-C',str(root),*args])
assert not git('status','--porcelain'),'Commit/review source inputs first'
commit=git('rev-parse','HEAD').decode().strip();tree=git('rev-parse','HEAD^{tree}').decode().strip()
out.mkdir(parents=True);inputs=out/'source-inputs'
with tarfile.open(fileobj=io.BytesIO(git('archive',commit))) as tar:tar.extractall(inputs,filter='data')
(inputs/'Package.resolved').unlink(missing_ok=True)
base='/Applications/Xcode.app/Contents/Developer';swift=base+'/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift'
env=dict(os.environ,DEVELOPER_DIR=base,COPYSTORY_APP_STORE='1',COPYSTORY_SHIPPING_RECONSTRUCTION='1',CLANG_MODULE_CACHE_PATH=str(out/'module-cache'),SWIFTPM_MODULECACHE_OVERRIDE=str(out/'module-cache'))
sdk=subprocess.check_output(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],env=env,text=True).strip()
command=[swift,'build','--build-system','native','--package-path',str(inputs),'--scratch-path',str(out/'swift-build'),'--disable-sandbox','--configuration','release','--triple','arm64-apple-macosx26.0','--sdk',sdk,'--product','CopyStory']
with (out/'compile.log').open('w') as log:subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
binpath=Path(subprocess.check_output(command+['--show-bin-path'],env=env,text=True).strip().splitlines()[-1])
stage=out/'staging/CopyStoryEngineering.xcarchive';app=stage/'Products/Applications/CopyStory.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Resources').mkdir()
shutil.copy2(binpath/'CopyStory',app/'Contents/MacOS/CopyStory');shutil.copy2(inputs/'Config/ShippingReconstruction-Info.plist',app/'Contents/Info.plist');shutil.copy2(inputs/'LICENSE',app/'Contents/Resources/LICENSE')
info={'ArchiveVersion':2,'CreationDate':datetime.now(timezone.utc).replace(tzinfo=None),'Name':'CopyStory source-only engineering','SchemeName':'manual-native-source-only','ApplicationProperties':{'ApplicationPath':'Applications/CopyStory.app','CFBundleIdentifier':'com.copystory.app','CFBundleShortVersionString':'1.0.0','CFBundleVersion':'0'},'CopyStoryManualEngineeringContainer':True}
(stage/'Info.plist').write_bytes(plistlib.dumps(info))
static=subprocess.check_output([os.sys.executable,str(inputs/'scripts/verify-shipping-reconstruction.py'),str(app)],text=True)
(out/'static-package-verification.json').write_text(static)
archive=out/'CopyStoryEngineering.xcarchive.tar.gz'
with tarfile.open(archive,'w:gz') as tar:tar.add(stage,arcname='CopyStoryEngineering.xcarchive')
checks=json.loads(static)
with tarfile.open(archive) as tar:
 for rel,h in checks['bundleFilesSHA256'].items():
  data=tar.extractfile('CopyStoryEngineering.xcarchive/Products/Applications/CopyStory.app/'+rel).read()
  assert hashlib.sha256(data).hexdigest()==h
manifest={'sourceCommit':commit,'sourceTree':tree,'command':command,'environment':{k:env[k] for k in ['DEVELOPER_DIR','COPYSTORY_APP_STORE','COPYSTORY_SHIPPING_RECONSTRUCTION','CLANG_MODULE_CACHE_PATH','SWIFTPM_MODULECACHE_OVERRIDE']},'inputException':'Package.resolved removed only from dependency-free copied inputs','archive':str(archive),'archiveSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),'executableSHA256':checks['bundleFilesSHA256']['Contents/MacOS/CopyStory'],'kind':'Manually assembled unsigned engineering xcarchive container, NOT xcodebuild archive/export or release candidate','registration':'No LaunchServices/register/install/launch command used; staging in .noindex and removed after verified compression; OS indexing/registry outcome not inspected','limits':'No runtime, signing, effective sandbox, App Store export or FRO22 acceptance'}
(out/'PACKAGE_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
shutil.rmtree(out/'staging') # Only our newly created, fully archived staging.
print(json.dumps(manifest,indent=2))
