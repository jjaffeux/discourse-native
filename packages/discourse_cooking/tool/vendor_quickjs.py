#!/usr/bin/env python3
"""Verify the pinned QuickJS source subset, or restore it from pinned upstream.

Run without arguments in CI. --restore downloads only the pinned commit and
checks every retained file before replacing files. It never rewrites the lock.
For upgrades, review upstream changes and deliberately update PROVENANCE.json.
"""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import urllib.request

root = Path(__file__).resolve().parents[1] / 'vendor' / 'quickjs'
lock = json.loads((root / 'PROVENANCE.json').read_text())
if sys.argv[1:] == ['--restore']:
    url = f"{lock['repository']}/archive/{lock['commit']}.tar.gz"
    data = urllib.request.urlopen(url).read()
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        prefix = archive.getmembers()[0].name.split('/')[0]
        restored = {}
        for name, digest in lock['files'].items():
            content = archive.extractfile(f'{prefix}/{name}').read()
            if hashlib.sha256(content).hexdigest() != digest:
                raise SystemExit(f'Upstream hash mismatch: {name}')
            restored[name] = content
    for name, content in restored.items():
        (root / name).write_bytes(content)
elif sys.argv[1:]:
    raise SystemExit('Usage: vendor_quickjs.py [--restore]')
for name, digest in lock['files'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Vendor hash mismatch: {name}')
print(f"Verified {len(lock['files'])} QuickJS files at {lock['commit']}")
