"""Check the exact raw JavaScript embedded in the desktop companion."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'lib/services/desktop/desktop_web_script.dart').read_text(encoding='utf-8')
script = source.split("r'''", 1)[1].rsplit("'''", 1)[0]
html = (root / 'lib/services/desktop/desktop_web_template.dart').read_text(encoding='utf-8')
ids = set(re.findall(r'id="([^"]+)"', html))
used = set(re.findall(r"\$\('([^']+)'\)", script))
missing = sorted(used - ids)
if missing:
    raise SystemExit('Missing desktop controls: ' + ', '.join(missing))
with tempfile.TemporaryDirectory(prefix='nyro-script-') as folder:
    path = Path(folder) / 'studio.js'
    path.write_bytes(script.encode('utf-8'))
    subprocess.run(['node', '--check', str(path)], check=True)
print(f'PASS: desktop JavaScript syntax and {len(used)} referenced controls.')
