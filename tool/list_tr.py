#!/usr/bin/env python3
"""List every string passed to tr() in lib/ (used to keep lib/l10n_ar.dart complete)."""
import re, pathlib, sys
LIT = r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")"""
def unesc(s): return re.sub(r"\\(.)", lambda m: {'n': '\n'}.get(m.group(1), m.group(1)), s)
keys = {}
for f in sorted(pathlib.Path('lib').rglob('*.dart')):
    if f.name in ('l10n_ar.dart', 'web_ui.dart'): continue
    t = f.read_text(encoding='utf-8')
    for m in re.finditer(r"\btr\(\s*" + LIT, t):
        keys.setdefault(unesc(m.group(1) if m.group(1) is not None else m.group(2)), f.name)
    # ternary: tr(cond ? 'a' : 'b'
    for m in re.finditer(r"\btr\([^'\"\n]*\?\s*" + LIT + r"\s*:\s*" + LIT, t):
        for g in (m.group(1) or m.group(2), m.group(3) or m.group(4)):
            keys.setdefault(unesc(g), f.name)
if __name__ == '__main__':
    for k, f in keys.items(): print(f"{f}\t{k!r}")
