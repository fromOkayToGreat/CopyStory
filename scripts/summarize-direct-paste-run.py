#!/usr/bin/env python3
"""Snapshot only this synthetic run's container logs; never real CopyStory data."""
import collections,json,pathlib,shutil,sys,uuid

output=pathlib.Path(sys.argv[1]).resolve()
run=str(uuid.UUID(sys.argv[2])).upper()
destination=output/'runs'/run
destination.mkdir(parents=True,exist_ok=True)
result={'run':run,'surfaces':{},'insertionProof':'not inferred from event posting'}
prototype='com.copystory.paste-probe.fro22' if (output/'CS Paste Probe.app').exists() else 'com.copystory.paste-prototype'
for role,bundle in [('prototype',prototype),
                    ('target','com.copystory.paste-fixture.target'),
                    ('decoy','com.copystory.paste-fixture.decoy')]:
    log=pathlib.Path.home()/'Library/Containers'/bundle/'Data/Library/Application Support/PasteExperiment'/run/'events.jsonl'
    records=[json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    assert all(row['run']==run for row in records)
    if log.exists(): shutil.copy2(log,destination/(role+'.jsonl'))
    counts=dict(collections.Counter(row['event'] for row in records))
    result['surfaces'][role]={'eventCounts':counts,
                              'postEventObservations':[row for row in records if 'postEventPreflight' in row or row['event']=='explicitPermissionRequest'],
                              'eventPairs':[row for row in records if row['event']=='eventPairPosted'],
                              'receivedEvents':[row for row in records if row['event'] in ['commandVDown','commandVUp']],
                              'insertions':[row for row in records if row['event'] in ['textInserted','imageInserted']]}
(destination/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({role:value['eventCounts'] for role,value in result['surfaces'].items()},indent=2))
