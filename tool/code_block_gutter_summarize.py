"""Summarize raw GUTTER_CASE / GUTTER_CALLBACK stdout captures."""
import json
import statistics
import sys
from pathlib import Path

results = []
for filename in sys.argv[1:]:
    case = None
    metadata = None
    samples = []
    for line in Path(filename).read_text().splitlines():
        if 'GUTTER_METADATA ' in line:
            metadata = json.loads(line.split('GUTTER_METADATA ', 1)[1])
        elif 'GUTTER_CASE ' in line:
            case = json.loads(line.split('GUTTER_CASE ', 1)[1])
        elif 'GUTTER_CALLBACK ' in line and case is not None:
            micros, count = map(int, line.split('GUTTER_CALLBACK ', 1)[1].split())
            assert count == case['lines']
            samples.append({**case, 'callbackMicros': micros})
            case = None
    assert 'GUTTER_DONE' in Path(filename).read_text()
    assert 'GUTTER_INVALID' not in Path(filename).read_text()
    assert metadata and metadata['semanticsEnabled']
    assert metadata['lifecycle'] == 'AppLifecycleState.resumed'
    assert all(s['semanticsEnabled'] for s in samples)
    assert len(samples) == 480, (filename, len(samples))
    groups = []
    for count in (20, 100, 500, 1000):
        for numbered in (False, True):
            group = [s for s in samples if s['retained'] and s['lines'] == count
                     and s['numbered'] == numbered]
            times = sorted(s['callbackMicros'] for s in group)
            groups.append({'lines': count, 'numbered': numbered, 'samples': len(times),
                           'medianMicros': statistics.median(times),
                           'minMicros': min(times), 'maxMicros': max(times)})
    results.append({'file': filename, 'metadata': metadata, 'groups': groups, 'rawSamples': samples})
print(json.dumps(results, indent=2))
