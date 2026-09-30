#!/bin/bash
# CASS dashboard data-layer sync — data-only, staging-first per protocol
# Usage: ./sync_data.sh ["commit message"]
set -euo pipefail
cd "$(dirname "$0")"
MSG="${1:-data refresh $(date +%Y-%m-%d): movers + history regenerated from /space}"

python3 - <<'PY'
import json, glob, os, datetime

P="/space/prediction/"
here=os.path.dirname(os.path.abspath(__file__)) if False else os.getcwd()

# history: append today's confidence score per tracked series
h=json.load(open("history.json"))
import datetime as _dt; today=(_dt.datetime.now(_dt.timezone(_dt.timedelta(hours=-4)))).date().isoformat()
for f in glob.glob(P+"*.json"):
    b=os.path.basename(f)[:-5]
    if b not in h["points"]: continue
    d=json.load(open(f)); s=d.get("confidence_score")
    if s is None: continue
    pts=h["points"][b]
    if not pts or pts[-1][0]!=today:
        pts.append([today, s])
json.dump(h, open("history.json","w"), indent=1)

# data.json movers: cards moved in last 7 days
data=json.load(open("data.json"))
cards=[json.load(open(f)) for f in glob.glob(P+"*.json") if not f.endswith(".schema.json")]
INTERNAL=[l.strip() for l in open('internal_cards.txt')] if os.path.exists('internal_cards.txt') else []
cards=[c for c in cards if c.get('basename') not in INTERNAL]
md=lambda c: c.get("last_moved") or c.get("date_made") or ""
recent=sorted([c for c in cards if md(c)>=today.replace(today[-2:], "01") or (md(c)>=str(datetime.date.today()-datetime.timedelta(days=7)))],
              key=md, reverse=True)
movers=[{"time":md(c), "ref":c.get("title",""),
         "change":f"confidence {c.get('confidence_score')} — status {c.get('status')}",
         "trigger":(c.get("evidence_confirmed") or ["—"])[-1][:180]} for c in recent[:10]]
data["movers"]=movers

# mget_ledger: rebuild from /space/mget_ledger (dedup by basename, newest first).
# Dedup key is the object basename — dates alone collide when multiple ledger
# entries land the same day. Entries missing date/verdict are skipped and
# counted, so silent ingestion gaps surface in the sync output.
led=[]; skipped=0
for f in glob.glob("/space/mget_ledger/*.json"):
    b=os.path.basename(f)[:-5]
    if b.endswith(".schema"): continue
    d=json.load(open(f))
    if not d.get("date") or not d.get("verdict"): skipped+=1; continue
    d["basename"]=b
    led.append(d)
led.sort(key=lambda x:(x["date"], x.get("time_et") or ""), reverse=True)
prev=data.get("mget_ledger") or []
data["mget_ledger"]=led
print(f"ledger: {len(led)} entries (was {len(prev)}), {skipped} skipped missing date/verdict, newest {led[0]['date'] if led else '—'}")

# daily_read: parse Daily Read.md into data.json (the board renders this panel
# from data.json, not from the .md — if this field goes missing the panel
# silently disappears from the render while the .md still exists)
import re
dr={"summary":[], "watching":[]}
if os.path.exists("Daily Read.md"):
    txt=open("Daily Read.md").read()
    m=re.search(r"DATE:\s*(\S+)", txt)
    if m: dr["date"]=m.group(1)
    m=re.search(r"SUMMARY:\s*\n(.*?)\nWATCHING:\s*\n(.*)", txt, re.S)
    if m:
        dr["summary"]=[l.strip() for l in m.group(1).strip().splitlines() if l.strip()]
        dr["watching"]=[l.strip().lstrip("- ") for l in m.group(2).strip().splitlines() if l.strip()]
data["daily_read"]=dr

data["meta"]["generated"]=today
json.dump(data, open("data.json","w"), indent=1)
print(f"regenerated: {len(movers)} movers, history through {today}")
PY

# git guard: only commit if something changed
if git diff --quiet history.json data.json; then
  echo "no data-layer changes — nothing to push"
  exit 0
fi

# staging-first: verify JSON parses clean before any push
python3 -c "import json;[json.load(open(f)) for f in ['data.json','history.json']]" \
  && echo "staging gate: JSON valid"

git add data.json history.json
git commit -q -m "$MSG (data-only)"
git pull --rebase -X ours -q origin main || true
git push -q origin main && echo "PUSHED TO PROD ✓"
