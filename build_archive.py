#!/usr/bin/env python3
# Daily Read archive builder — converts Daily Read*.md into archive/<slug>.html
# pages styled like the dashboard, and regenerates archive/index.json (the
# client-side search index). Called by sync_data.sh so the archive grows
# automatically with every push. 2026-10-14, owner-approved feature.
import json, glob, os, re, html as H, subprocess, sys, datetime

REPO = os.path.dirname(os.path.abspath(__file__))
ARCH = os.path.join(REPO, "archive")
os.makedirs(ARCH, exist_ok=True)

TEMPLATE = """<!doctype html><html lang=en><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>{title} — CASS Daily Read Archive</title>
<link rel=stylesheet href="../style.css">
<body><div class=z4><div class=z21><a class=znav href="../archive.html">← Archive</a>
<span class=z0>{edate}</span></div>
<h1>Daily Read <span class=z18>— {pretty}</span></h1>
<p class=z11>{filed}</p></div>
<article class=z37 style="padding:18px 20px">
{body}
</article>
<p class=z13 style="text-align:center;margin:18px 0">CASS Intelligence Board · <a href="../archive.html">back to archive</a> · <a href="../Internal%20Telemetry.html">live board</a></p>
</body></html>"""


MONTHS={"January":1,"February":2,"March":3,"April":4,"May":5,"June":6,"July":7,
        "August":8,"September":9,"October":10,"November":11,"December":12}
def date_from_content(content):
    m=re.search(r"DATE:\s*(\d{4}-\d{2}-\d{2})",content)
    if m: return m.group(1)
    m=re.search(r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),\s+(\d{4})",content)
    if m: return f"{m.group(3)}-{MONTHS[m.group(1)]:02d}-{int(m.group(2)):02d}"
    return None

def slugify(name, content=""):
    stem = re.sub(r"\.md$", "", name)
    m = re.search(r"(\d{4}-\d{2}-\d{2})", stem)
    if not m:  # undated source file (Daily Read.md) — take DATE: from content
        m = re.search(r"DATE:\s*(\d{4}-\d{2}-\d{2})", content)
    base = m.group(1) if m else stem
    tag = "evening" if "evening" in stem.lower() else "morning"
    return f"daily-read-{base}-{tag}"

def to_html(md_path):
    out = subprocess.run(["pandoc", "-f", "markdown", "-t", "html", md_path],
                         capture_output=True, text=True, check=True)
    return out.stdout

def plain_text(html_body):
    t = re.sub(r"<script.*?</script>|<style.*?</style>", " ", html_body, flags=re.S)
    t = re.sub(r"<[^>]+>", " ", t)
    return re.sub(r"\s+", " ", H.unescape(t)).strip()

entries = []
for md in sorted(glob.glob(os.path.join(REPO, "Daily Read*.md"))):
    name = os.path.basename(md)
    raw = open(md).read()
    slug = slugify(name, raw) if re.search(r"\d{4}-\d{2}-\d{2}", name) else slugify(date_from_content(raw) or name, raw)
    body = to_html(md)
    txt = plain_text(body)
    m = re.search(r"DATE:\s*(\S+)", txt)
    edate = (date_from_content(raw) or slug)
    h1 = next((l for l in open(md).read().splitlines() if l.startswith("# ")), name)
    pretty = re.sub(r"^# |^The (Morning|Evening) Read — ", "", h1).strip()
    if not pretty or pretty == "The Daily Read":
        # bare header — synthesize a dated title from the edition date
        d = date_from_content(raw) or slug
        if not d or not re.match(r"\d{4}-\d{2}-\d{2}", d):
            d = "undated"
        y, mo, dy = (d.split("+") + ["", ""])[0].split("-") if re.match(r"\d{4}-\d{2}-\d{2}", d) else ("", "", "")
        month = {v: k for k, v in MONTHS.items()}.get(int(mo) if mo else 0, "")
        edition = "Evening" if "evening" in (raw[:400].lower() + h1.lower() + name.lower()) else "Morning"
        weekday = datetime.date(int(y), int(mo), int(dy)).strftime("%A") if y else ""
        pretty = f"The {edition} Read — {weekday}, {month} {int(dy)}, {y}".replace(" , ", " ")
    fm = re.search(r"Filed ~(\d{2}:\d{2} ET)", txt)
    filed = f"Filed ~{fm.group(1)}" if fm else ""
    html_doc = TEMPLATE.format(title=H.escape(pretty), edate=edate, pretty=H.escape(pretty),
                               filed=filed, body=body, file=H.escape(name))
    out_path = os.path.join(ARCH, slug + ".html")
    open(out_path, "w").write(html_doc)
    # summary: first SUMMARY block bullets (search hits show these too)
    sm = re.search(r"SUMMARY:\s*\n(.*?)(?:\nWATCHING:|\n)", txt)
    summary = sm.group(1).strip() if sm else ""
    entries.append({"date": edate, "title": pretty, "file": f"archive/{slug}.html",
                    "slug": slug, "filed": filed, "summary": summary, "text": txt})
    print(f"archived: {name} -> archive/{slug}.html ({len(txt)} chars)")

entries.sort(key=lambda e: e["date"], reverse=True)
idx = [{k: e[k] for k in ("date", "title", "file", "filed", "summary")} | {"text": e["text"]} for e in entries]
json.dump(idx, open(os.path.join(ARCH, "index.json"), "w"), indent=1)
print(f"index: {len(idx)} editions -> archive/index.json")
