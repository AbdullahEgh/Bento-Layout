#!/usr/bin/env python3
"""Create Bento's persistent free signing identity once; never replace an existing key."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

os.umask(0o077)
root = Path.home() / 'Library/Application Support/BentoSigning'
root.mkdir(parents=True, exist_ok=True)
metadata = root / 'identity.json'
if metadata.exists():
    print('Existing Bento signing identity retained: ' + str(metadata))
    raise SystemExit(0)
public_copy = Path(__file__).resolve().parent.parent / 'CodeSigningCertificate.pem'
if public_copy.exists():
    raise SystemExit('A public release identity already exists. Restore its private backup; do not generate a replacement.')
password = secrets.token_urlsafe(48)
keychain = root / 'BentoSigning.keychain-db'
if keychain.exists() or (root / 'identity.p12').exists():
    raise SystemExit('Incomplete identity setup exists. Inspect it before retrying; no key was replaced.')

def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stderr.replace(password, '<redacted>'))
    return result.stdout

with tempfile.TemporaryDirectory(prefix='bento-create-signing-') as temporary:
    work = Path(temporary)
    config = work / 'certificate.cnf'
    config.write_text('[req]\ndistinguished_name=subject\nx509_extensions=extensions\nprompt=no\n[subject]\nCN=Bento Layout Release Signing\nO=Bento Layout\n[extensions]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
    certificate = root / 'certificate.pem'
    run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-sha256', '-nodes', '-days', '3650', '-config', str(config), '-keyout', str(work / 'key.pem'), '-out', str(certificate)])
    run(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', str(work / 'key.pem'), '-in', str(certificate), '-out', str(root / 'identity.p12'), '-passout', 'env:BENTO_P12_PASSWORD'], env=dict(os.environ, BENTO_P12_PASSWORD=password))
    run(['/usr/bin/security', 'create-keychain', '-p', password, str(keychain)])
    run(['/usr/bin/security', 'unlock-keychain', '-p', password, str(keychain)])
    run(['/usr/bin/security', 'set-keychain-settings', '-lut', '21600', str(keychain)])
    run(['/usr/bin/security', 'import', str(root / 'identity.p12'), '-k', str(keychain), '-P', password, '-T', '/usr/bin/codesign'])
    run(['/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, str(keychain)])
    # The encrypted backup stays outside the repository; its password is in Keychain.
    run(['/usr/bin/security', 'add-generic-password', '-a', 'com.abdullahegh.bento', '-s', 'Bento Code Signing Backup', '-w', password])
    fingerprint = run(['/usr/bin/openssl', 'x509', '-in', str(certificate), '-noout', '-fingerprint', '-sha1']).strip().split('=')[1].replace(':', '')
    metadata.write_text(json.dumps({'identity': fingerprint, 'keychain': str(keychain), 'certificate': str(certificate)}, indent=2) + '\n')
    shutil.copy(certificate, public_copy)
print('Persistent Bento identity created. Private material is outside the repository; only the public certificate is copied into it.')
print('Identity metadata: ' + str(metadata))
