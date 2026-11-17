"""Local lexical validation only. Flutter compiler checks run in GitHub Actions."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SAFE = 'safe.directory=' + ROOT.as_posix()
diff_args = ['--name-only'] + ([sys.argv[1]] if len(sys.argv) > 1 else [])
changed = subprocess.check_output(['git', '-c', SAFE, 'diff', *diff_args], cwd=ROOT, text=True).splitlines()
untracked = subprocess.check_output(['git', '-c', SAFE, 'ls-files', '--others', '--exclude-standard'], cwd=ROOT, text=True).splitlines()
paths = sorted(set(changed + untracked))
emoji = re.compile('[\U0001F000-\U0001FAFF\u2600-\u26ff\u2700-\u27bf\ud800-\udfff]')

def validate(text):
    n = len(text)
    def string(i):
        raw = i > 0 and text[i-1] == 'r'
        q = text[i:i+3] if text[i:i+3] in ("'''", '"""') else text[i]
        i += len(q)
        while i < n:
            if text.startswith(q, i): return i + len(q)
            if not raw and text[i] == '\\': i += 2; continue
            if not raw and text.startswith('${', i): i = code(i+2, '}'); continue
            i += 1
        raise ValueError('Unterminated string')
    def code(i, end=None):
        while i < n:
            if text.startswith('//', i):
                j = text.find('\n', i); i = n if j < 0 else j+1; continue
            if text.startswith('/*', i):
                depth = 1; i += 2
                while i < n and depth:
                    if text.startswith('/*', i): depth += 1; i += 2
                    elif text.startswith('*/', i): depth -= 1; i += 2
                    else: i += 1
                if depth: raise ValueError('Unterminated comment')
                continue
            c = text[i]
            if c in "\"'": i = string(i); continue
            if c in '({[': i = code(i+1, {'(': ')', '{': '}', '[': ']'}[c]); continue
            if c in ')}]':
                if c != end: raise ValueError(f'Unexpected {c} at line {text[:i].count(chr(10))+1}')
                return i+1
            i += 1
        if end: raise ValueError(f'Missing {end}')
        return i
    code(0)

errors = []
for name in paths:
    path = ROOT / name
    if not path.is_file() or path.suffix not in {'.dart', '.kt', '.xml', '.yaml', '.yml', '.md', '.py', '.gradle'}: continue
    text = path.read_text(encoding='utf-8')
    if emoji.search(text): errors.append(f'{name}: emoji found')
    if path.suffix == '.dart':
        try: validate(text)
        except ValueError as e: errors.append(f'{name}: {e}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print(f'PASS: zero-emoji scan of {len(paths)} changed/new files; Dart lexical delimiter checks passed.')
