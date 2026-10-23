#!/bin/bash
# Separate arm64 experiment; preserves production sources/lockfile/artifacts.
set -euo pipefail
COPYSTORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COPYSTORY_PACKAGE="$COPYSTORY_ROOT/scripts/sandbox/DirectPaste"
mkdir -p "$COPYSTORY_ROOT/.build"
COPYSTORY_OUTPUT="$(mktemp -d "$COPYSTORY_ROOT/.build/direct-paste-XXXXXX")"
COPYSTORY_SIGNER="${COPYSTORY_PROTOTYPE_SIGNER:--}"
ditto "$COPYSTORY_PACKAGE" "$COPYSTORY_OUTPUT/package"
swift build --package-path "$COPYSTORY_OUTPUT/package" --scratch-path "$COPYSTORY_OUTPUT/swift" -c debug --triple arm64-apple-macosx26.0
COPYSTORY_BIN="$(swift build --package-path "$COPYSTORY_OUTPUT/package" --scratch-path "$COPYSTORY_OUTPUT/swift" -c debug --triple arm64-apple-macosx26.0 --show-bin-path)"
python3 - "$COPYSTORY_ROOT" "$COPYSTORY_OUTPUT" "$COPYSTORY_BIN" <<'PY'
import hashlib,json,pathlib,plistlib,shutil,subprocess,sys
root,out,binpath=map(pathlib.Path,sys.argv[1:])
source=out/'package'
hashes={'scripts/sandbox/DirectPaste/'+str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(source.rglob('*.swift'))}
for relative in ['scripts/build-direct-paste-prototype.sh','scripts/verify-direct-paste-prototype.py','Config/AppStore.entitlements']:
    hashes[relative]=hashlib.sha256((root/relative).read_bytes()).hexdigest()
manifest={'baseCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
          'sourceDirty':True,'sourceHashes':hashes,'architecture':'arm64','minimumOS':'26.0',
          'os':subprocess.check_output(['sw_vers'],text=True),'build':'prototype-11','generalPasteboardUsed':False}
for name,exe,bundle,role in [('CS Paste Probe','PastePrototype','com.copystory.paste-probe.fro22',None),
                            ('CS Paste Target','PasteFixture','com.copystory.paste-fixture.target','target'),
                            ('CS Paste Decoy','PasteFixture','com.copystory.paste-fixture.decoy','decoy')]:
    app=out/(name+'.app'); (app/'Contents/MacOS').mkdir(parents=True)
    shutil.copy2(binpath/exe,app/'Contents/MacOS'/exe)
    info={'CFBundleName':name,'CFBundleDisplayName':name,'CFBundleIdentifier':bundle,'CFBundleExecutable':exe,
          'CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.0.11','CFBundleVersion':'11',
          'LSMinimumSystemVersion':'26.0','NSPrincipalClass':'NSApplication','LSUIElement':role is None,
          'CopyStoryDirectPasteExperiment':True}
    if role: info['PasteFixtureRole']=role
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
for COPYSTORY_NAME in 'CS Paste Probe' 'CS Paste Target' 'CS Paste Decoy'; do
    codesign --force --options runtime --timestamp=none --sign "$COPYSTORY_SIGNER" \
        --entitlements "$COPYSTORY_ROOT/Config/AppStore.entitlements" "$COPYSTORY_OUTPUT/$COPYSTORY_NAME.app"
    codesign --verify --deep --strict --verbose=2 "$COPYSTORY_OUTPUT/$COPYSTORY_NAME.app"
done
python3 "$COPYSTORY_ROOT/scripts/verify-direct-paste-prototype.py" "$COPYSTORY_OUTPUT"
if [[ "${1:-}" == --stable-runtime ]]; then
    # A single known path for this new identity. Never replace the previously
    # granted/tested bundle automatically; subsequent rebuilds remain staged.
    COPYSTORY_RUNTIME="$COPYSTORY_ROOT/.build/fro22-runtime"
    [[ ! -e "$COPYSTORY_RUNTIME" ]] || { echo 'Stable runtime already exists; preserve it and review the new staged build.' >&2; exit 1; }
    mkdir "$COPYSTORY_RUNTIME"
    for COPYSTORY_NAME in 'CS Paste Probe' 'CS Paste Target' 'CS Paste Decoy'; do
        ditto "$COPYSTORY_OUTPUT/$COPYSTORY_NAME.app" "$COPYSTORY_RUNTIME/$COPYSTORY_NAME.app"
    done
    cp "$COPYSTORY_OUTPUT/source-manifest.json" "$COPYSTORY_RUNTIME/source-manifest.json"
    python3 "$COPYSTORY_ROOT/scripts/verify-direct-paste-prototype.py" "$COPYSTORY_RUNTIME"
    echo "Stable runtime: $COPYSTORY_RUNTIME"
fi
echo "$COPYSTORY_OUTPUT"
