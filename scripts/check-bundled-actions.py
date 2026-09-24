#!/usr/bin/env python3
"""Verify the built app contains its installable actions and four UI locales."""
import json
import plistlib
import sys
import zipfile
from pathlib import Path

app = Path(sys.argv[1])
resources = app / 'Contents/Resources'
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
assert info['CFBundleDevelopmentRegion'] == 'en'
for language in ('en', 'nl', 'fr', 'es'):
    assert (resources / f'{language}.lproj/Localizable.strings').is_file(), language

archive = resources / 'BundledExtensions/talos-actions.talos'
assert archive.is_file() and archive.stat().st_size > 0
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None
    manifest = json.loads(package.read('package.json'))
    commands = {item['name']: item for item in manifest['commands']}
    assert {'crop', 'convert', 'archive', 'compress', 'convert-docx'} <= commands.keys()
    for name in ('convert', 'convert-png', 'convert-jpg', 'convert-docx'):
        assert 'com.adobe.pdf' in commands[name]['supportedFileTypes'], name
    assert any(name.startswith('vendor/bin/') and name.endswith('/pdf-tool') for name in package.namelist())
    for language in ('en', 'nl', 'fr', 'es'):
        locale = manifest['talos']['locales'][language]
        assert json.loads(package.read(locale))
    assert package.read('extension.mjs')
print('Passed: bundled actions and four app/extension locales are in Talos.app')
