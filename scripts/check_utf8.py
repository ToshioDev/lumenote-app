from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {'.git', '.dart_tool', '.gradle', '__pycache__', 'build', 'node_modules', 'Pods', 'ephemeral', '.plugin_symlinks'}
BINARY_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.gif', '.ico', '.webp', '.m4a', '.mp3', '.mp4', '.mov', '.wav', '.ttf', '.otf', '.woff', '.woff2', '.lock', '.bin', '.jar', '.probe'}
MOJIBAKE = re.compile(r'[ÃÂâƒ�]')

failures = []
for path in ROOT.rglob('*'):
    if path.is_symlink() or any(part in SKIP_DIRS for part in path.parts):
        continue
    try:
        if not path.is_file():
            continue
    except OSError:
        continue
    if path.name == 'check_utf8.py':
        continue
    if path.suffix.lower() in BINARY_EXTENSIONS:
        continue
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeDecodeError as error:
        failures.append(f'{path.relative_to(ROOT)}: invalid UTF-8 ({error})')
        continue
    if '\ufffd' in text or MOJIBAKE.search(text):
        failures.append(f'{path.relative_to(ROOT)}: mojibake or replacement character found')

if failures:
    print('\n'.join(failures))
    sys.exit(1)
print('UTF-8 validation passed.')
