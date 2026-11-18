"""Prevent fixed blue accents from returning to theme-aware UI code."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
paths = list((root / 'lib/pages').rglob('*.dart')) + list((root / 'lib/widgets').rglob('*.dart'))
paths.append(root / 'lib/services/vault_service.dart')
fixed = re.compile(r'\bgoogle(?:Blue|BlueContainer|OnBlueContainer)\b|\bColors\.blue\b|Color\(0xFF(?:315DA8|1A73E8|4285F4|E8F0FE|D3E3FD|BFDBFE|DCE7FD|D2E3FC|EFF6FF|DBEAFE|E3F2FD)\)', re.I)
failures = []
for path in paths:
    if 'bitchat' in path.parts:
        continue
    for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if fixed.search(line):
            failures.append(f'{path.relative_to(root)}:{number}: fixed UI accent')
if failures:
    raise SystemExit('\n'.join(failures))
print('PASS: UI accents use inherited theme roles; BitChat remains outside this change.')
