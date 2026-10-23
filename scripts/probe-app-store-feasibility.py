#!/usr/bin/env python3
"""Exercise the signed sandbox app using only disposable synthetic fixtures."""
import json
import pathlib
import subprocess
import uuid

root = pathlib.Path(__file__).resolve().parent.parent
output = root / '.build/app-store-feasibility'
app = output / 'CopyStory Sandbox.app/Contents/MacOS/CopyStory'
fixture = output / 'outside-synthetic-fixture.txt'
fixture.write_text('synthetic sandbox denial fixture\n')
run = str(uuid.uuid4())
(output / 'probe-run-id.txt').write_text(run + '\n')
args = [str(app), '--sandbox-probe', '--probe-run', run, '--outside-fixture', str(fixture)]
for phase, extra in [('write', []), ('read', ['--probe-read'])]:
    result = subprocess.run(args + extra, capture_output=True, text=True, timeout=40)
    (output / f'probe-{phase}.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit(f'{phase} failed ({result.returncode}); see probe-{phase}.log')
    report = json.loads(result.stdout)
    assert report['pasteEventsPosted'] is False
    assert report['automaticPasteVerified'] is False
    print(json.dumps(report, sort_keys=True))
result = subprocess.run([str(app)], capture_output=True, text=True, timeout=10)
assert result.returncode != 0 and 'require --demo or --sandbox-probe' in result.stderr
print('Normal capture launch blocked; production history and general clipboard were not used.')
