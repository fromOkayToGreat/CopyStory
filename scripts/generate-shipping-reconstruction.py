#!/usr/bin/env python3
"""Deterministic local Xcode project. No builds, signing, launch or network."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent.parent
objects={}
def ident(key):return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def add(key,isa,**fields):
 i=ident(key);objects[i]=dict(isa=isa,**fields);return i
proj=ident('project');app=ident('app');core=ident('core')
refs=[]
def file(path,typ):
 i=add('file:'+path,'PBXFileReference',path=path,sourceTree='SOURCE_ROOT',lastKnownFileType=typ);refs.append(i);return i
appSources=[];coreSources=[]
for group,collector in [('CopyStory',appSources),('CopyStoryCore',coreSources)]:
 for p in sorted((root/'Sources'/group).glob('*.swift')):
  if p.name=='SandboxProbe.swift':continue
  rel=str(p.relative_to(root));f=file(rel,'sourcecode.swift');collector.append(add('source:'+rel,'PBXBuildFile',fileRef=f))
config=file('Config/ShippingReconstruction.xcconfig','text.xcconfig')
for rel in ['Config/ShippingReconstruction-Info.plist','Config/AppStore.entitlements']:file(rel,'text.plist.xml')
license=file('LICENSE','text');resource=add('resource:LICENSE','PBXBuildFile',fileRef=license)
carbon=add('framework:Carbon','PBXFileReference',path='System/Library/Frameworks/Carbon.framework',sourceTree='SDKROOT',lastKnownFileType='wrapper.framework')
refs.append(carbon)
carbonBuild=add('link:Carbon','PBXBuildFile',fileRef=carbon)
coreProduct=add('product:core','PBXFileReference',path='libCopyStoryCore.a',sourceTree='BUILT_PRODUCTS_DIR',explicitFileType='archive.ar')
appProduct=add('product:app','PBXFileReference',path='CopyStory.app',sourceTree='BUILT_PRODUCTS_DIR',explicitFileType='wrapper.application')
linkCore=add('link:core','PBXBuildFile',fileRef=coreProduct)
def phase(key,isa,files):return add(key,isa,buildActionMask=2147483647,files=files,runOnlyForDeploymentPostprocessing=0)
corePhase=phase('sources:core','PBXSourcesBuildPhase',coreSources)
appPhase=phase('sources:app','PBXSourcesBuildPhase',appSources)
linkPhase=phase('frameworks:app','PBXFrameworksBuildPhase',[linkCore,carbonBuild])
resources=phase('resources:app','PBXResourcesBuildPhase',[resource])
def configs(kind):
 ids=[]
 for name in ['Debug','Release']:
  settings={'PRODUCT_NAME':'CopyStoryCore' if kind=='core' else 'CopyStory','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','CLANG_ENABLE_MODULES':'YES'}
  if kind=='core':settings.update(DEFINES_MODULE='YES',PRODUCT_MODULE_NAME='CopyStoryCore',SKIP_INSTALL='YES')
  if kind=='app':settings.update(SKIP_INSTALL='NO',INSTALL_PATH='$(LOCAL_APPS_DIR)',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/../Frameworks'])
  ids.append(add('config:'+kind+name,'XCBuildConfiguration',baseConfigurationReference=config,buildSettings=settings,name=name))
 return add('configs:'+kind,'XCConfigurationList',buildConfigurations=ids,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
coreCfg=configs('core');appCfg=configs('app');projectCfg=configs('project')
proxy=add('proxy','PBXContainerItemProxy',containerPortal=proj,proxyType=1,remoteGlobalIDString=core,remoteInfo='CopyStoryCore')
dep=add('dependency','PBXTargetDependency',target=core,targetProxy=proxy)
add('core','PBXNativeTarget',buildConfigurationList=coreCfg,buildPhases=[corePhase],buildRules=[],dependencies=[],name='CopyStoryCore',productName='CopyStoryCore',productReference=coreProduct,productType='com.apple.product-type.library.static')
add('app','PBXNativeTarget',buildConfigurationList=appCfg,buildPhases=[appPhase,linkPhase,resources],buildRules=[],dependencies=[dep],name='CopyStory',productName='CopyStory',productReference=appProduct,productType='com.apple.product-type.application')
products=add('products','PBXGroup',children=[appProduct,coreProduct],name='Products',sourceTree='<group>')
main=add('main','PBXGroup',children=refs+[products],sourceTree='<group>')
add('project','PBXProject',attributes={'LastUpgradeCheck':'2700','BuildIndependentTargetsInParallel':'YES'},buildConfigurationList=projectCfg,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,core])
def encode(v,depth=0):
 if isinstance(v,dict):return '{\n'+''.join('\t'*(depth+1)+json.dumps(str(k))+' = '+encode(x,depth+1)+';\n' for k,x in v.items())+'\t'*depth+'}'
 if isinstance(v,list):return '('+', '.join(encode(x,depth) for x in v)+')'
 return json.dumps(v) if isinstance(v,str) else str(v)
p=root/'CopyStoryShipping.xcodeproj';p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':proj})+'\n')
scheme=p/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'CopyStoryShipping.xcscheme').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'''+app+'''" BuildableName="CopyStory.app" BlueprintName="CopyStory" ReferencedContainer="container:CopyStoryShipping.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="NO"/></Scheme>
''')
print(p)
