"""Bump the human version and strictly increasing Sparkle build number."""
import pathlib
import plistlib
import re
import sys

version = sys.argv[1]
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
    sys.exit('Use a version such as 1.2.1')
file = pathlib.Path('Resources/Info.plist')
info = plistlib.loads(file.read_bytes())
old = info['CFBundleShortVersionString']
if tuple(map(int, version.split('.'))) <= tuple(map(int, old.split('.'))):
    sys.exit(f'New version must be greater than {old}')
info['CFBundleShortVersionString'] = version
info['CFBundleVersion'] = str(int(info['CFBundleVersion']) + 1)
file.write_bytes(plistlib.dumps(info, sort_keys=False))
readme = pathlib.Path('Resources/Read Me.txt')
text = readme.read_text()
readme.write_text(re.sub(r'^Ruller [^\n]+', f'Ruller {version}', text, count=1))
print(f"Ruller {old} → {version}, build {info['CFBundleVersion']}")
