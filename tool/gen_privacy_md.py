#!/usr/bin/env python3
"""Regenerates PRIVACY.md from assets/privacy.json (the single source used by the app)."""
import json
d = json.load(open("assets/privacy.json", encoding="utf-8"))
md = ["# PocketServer\n"]
for k in ("en", "ar"):
    t = d[k]
    md.append(f"## {t['title']}\n\n_{t['updated']}_\n\n{t['intro']}\n")
    for s in t["sections"]:
        md.append(f"### {s['h']}\n\n{s['p']}\n")
    md.append("\n---\n")
open("PRIVACY.md", "w", encoding="utf-8").write("\n".join(md))
