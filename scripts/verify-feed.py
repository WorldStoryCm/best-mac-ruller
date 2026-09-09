"""Validate release metadata and both Ed25519 signatures before publishing."""
import base64
import pathlib
import plistlib
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

feed, archive = map(pathlib.Path, sys.argv[1:3])
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
with zipfile.ZipFile(archive) as z:
    info = plistlib.loads(z.read('Ruller.app/Contents/Info.plist'))
trusted = plistlib.loads((pathlib.Path(__file__).resolve().parent.parent / 'Resources/Info.plist').read_bytes())
assert info['SUPublicEDKey'] == trusted['SUPublicEDKey'], 'Archive does not use the trusted Ruller signing key'
assert info['CFBundleIdentifier'] == trusted['CFBundleIdentifier'], 'Wrong application in archive'
root = ET.parse(feed).getroot()
items = [x for x in root.findall('./channel/item') if x.findtext(sparkle + 'version') == info['CFBundleVersion']]
assert len(items) == 1, 'Feed must contain exactly one entry for the current build'
item = items[0]
assert item.findtext(sparkle + 'shortVersionString') == info['CFBundleShortVersionString']
enclosure = item.find('enclosure')
expected_url = f"https://github.com/WorldStoryCm/best-mac-ruller/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}"
assert enclosure.get('url') == expected_url, 'Unexpected update download URL'
assert int(enclosure.get('length')) == archive.stat().st_size, 'Archive length mismatch'
assert len(base64.b64decode(enclosure.get(sparkle + 'edSignature'), validate=True)) == 64, 'Missing EdDSA signature'
assert info['SUVerifyUpdateBeforeExtraction'] and info['SURequireSignedFeed']
assert item.findtext(sparkle + 'minimumSystemVersion') == '13.0'
data = feed.read_bytes()
# Sparkle 2.9 appends its signature block to the exact signed XML bytes.
block = re.search(rb'<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?\Z', data)
assert block is not None, 'Feed signature block missing'
assert block.start() == int(block[2]), 'Signed feed content length mismatch'
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=os.path.join(tempfile.gettempdir(), 'ruller-clang-cache'))
verifier = pathlib.Path(__file__).with_name('verify-signature.swift')
with tempfile.NamedTemporaryFile() as content:
    content.write(data[:block.start()]); content.flush()
    for file, signature in ((content.name, block[1].decode()), (str(archive), enclosure.get(sparkle + 'edSignature'))):
        subprocess.run(['swift', str(verifier), info['SUPublicEDKey'], file, signature], check=True, env=env)
print(f"Feed verified: Ruller {info['CFBundleShortVersionString']}, build {info['CFBundleVersion']}, signed {archive.stat().st_size} byte archive")
