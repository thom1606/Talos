#!/usr/bin/env python3
"""Check the actual built app, rather than only the pre-build extension artifact."""
import hashlib
import json
from pathlib import Path
import sys
import zipfile

resources = Path(sys.argv[1]) / 'Contents/Resources'
archive = resources / 'built-in-actions.talos'
assert not (resources / 'built-in-actions.zip').exists(), 'Stale ZIP in app bundle'
manifest = json.loads((resources / 'built-in-actions.json').read_text())
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest['release']['sha256']
with zipfile.ZipFile(archive) as package:
    embedded = json.loads(package.read('config.json'))
    assert embedded['id'] == 'com.talos.actions'
    assert embedded['runtime'] == 'javascript'
    assert package.read(embedded['entrypoint'])
    assert {action['id'] for action in embedded['actions']} == {'convert', 'archive', 'metadata', 'compress', 'crop'}
    expected = {key: value for key, value in manifest.items() if key != 'release'}
    assert embedded == expected
print('Passed: app bundles the matching .talos archive, checksum, manifest and five actions')
