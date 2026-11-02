#!/usr/bin/env python3
"""Strip internal card keys (z37, z38 …) from published page prose.

Why a separate pass: those keys are the board's internal class names, and analyst
notes written on the machine used them as shorthand for "this card" — so they
reached published text. The renderer scrubs what it builds, but parts of the page
(the legacy deep-dive blocks under the big-questions cards) were baked long before
the renderer existed and nothing regenerates them. Rather than trust every writer,
the last step before the gate rewrites the tokens in text nodes and reports what
it touched.

Runs from sync_data.sh. Safe to run twice. --check exits 1 if anything remains.
"""
import re, sys, glob, os

DIR = os.path.dirname(os.path.abspath(__file__))
TOK = re.compile(r"\bz(?:27|37|38)\b")
CHECK = "--check" in sys.argv

def scrub_html(path):
    h = open(path, encoding="utf-8").read()
    parts = re.split(r"(<[^>]+>)", h)
    n = 0
    for i, p in enumerate(parts):
        if p.startswith("<"):
            continue
        new = TOK.subn("card", p)
        if new[1]:
            n += new[1]
            parts[i] = new[0]
    if n and not CHECK:
        open(path, "w", encoding="utf-8").write("".join(parts))
    return n

total = 0
for f in sorted(glob.glob(os.path.join(DIR, "*.html"))):
    n = scrub_html(f)
    if n:
        total += n
        print(f"  scrubbed {n} internal key(s) from {os.path.basename(f)}")
print(f"scrub_internal_keys: {total} token(s) {'found' if CHECK else 'removed'}")
sys.exit(1 if (CHECK and total) else 0)
