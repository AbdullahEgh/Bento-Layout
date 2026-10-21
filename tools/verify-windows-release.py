"""Fail closed before release: validate OTA identity, version and every ZIP file."""
import hashlib
import json
import os
from pathlib import Path
import sys
import zipfile

folder = Path(sys.argv[1])
tag = os.environ['GITHUB_REF_NAME']
metadata = json.loads((folder / 'Bento-windows-release.json').read_text(encoding='utf-8-sig'))
assert tag == 'v' + metadata['Version'], 'Tag must match Windows assembly/package version'
assert metadata['AppId'] == 'Bento.Windows' and metadata['Platform'] == 'win-x64'
assert metadata['Asset'] == 'Bento-win-x64.zip'
archive = folder / metadata['Asset']
assert hashlib.sha256(archive.read_bytes()).hexdigest().lower() == metadata['Sha256'].lower()
with zipfile.ZipFile(archive) as package:
    manifest = json.loads(package.read('bento-release.json').decode('utf-8-sig'))
    assert (manifest['AppId'], manifest['Platform'], manifest['Version']) == ('Bento.Windows', 'win-x64', metadata['Version'])
    names = {entry.filename for entry in package.infolist() if not entry.is_dir()}
    assert names == set(manifest['Files']) | {'bento-release.json'}, 'Unexpected/unhashed package file'
    assert {'Bento.exe', 'Bento.dll', 'Bento.Updater.exe', 'Bento.Core.dll'} <= names
    for name, digest in manifest['Files'].items():
        assert '/' not in name and '\\' not in name and name not in ('.', '..')
        assert hashlib.sha256(package.read(name)).hexdigest().lower() == digest.lower(), name
print('PASS: Windows tag, OTA identity, metadata, archive and every file hash')
if len(sys.argv) > 2:
    source = json.loads(Path(sys.argv[2]).read_text())
    assert source['tag_name'] == 'macos-v0.2.44' and not source['draft'] and not source['prerelease']
    asset = next(a for a in source['assets'] if a['name'] == 'Bento-macos-universal.zip')
    assert asset['digest'].startswith('sha256:')
    assert hashlib.sha256((folder / asset['name']).read_bytes()).hexdigest() == asset['digest'][7:]
    print('PASS: included Mac archive exactly matches existing macOS 0.2.44 asset')
