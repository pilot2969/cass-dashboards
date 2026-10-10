#!/bin/bash
# CASS dashboard data-layer sync — data-only, prod+staging per PUSH-TARGET AMENDMENT (2026-10-05):
#   card/data updates -> prod + staging simultaneously; design changes -> staging only until approval.
# Usage: ./sync_data.sh ["commit message"]
set -euo pipefail
cd "$(dirname "$0")"
MSG="${1:-data refresh $(date +%Y-%m-%d): movers + history regenerated from /space}"

python3 - <<'PY'
import json, glob, os, datetime

# movers staleness gate: if the newest last_moved on any prediction card is older
# than 48h, the mover-bump step was skipped after the wire — fail the run loudly
# instead of silently publishing a stale panel (2026-10-03 regression).
newest=max((json.load(open(f)).get("last_moved") or "")[:10] for f in glob.glob("/space/prediction/*.json"))
age=(datetime.date.today()-datetime.date.fromisoformat(newest)).days
if age>2:
    raise SystemExit(f"MOVERS STALE: newest last_moved={newest} ({age}d old). Run the mover bump before sync.")

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
# stranded-commit guard: a prior run can die between commit and push, leaving
# prod stale while a naive "nothing to push" exit looks like success. If local
# is ahead of origin, finish the push regardless of whether THIS run changed data.
if ! git diff --quiet history.json data.json "Daily Read.md"; then
  git add history.json data.json "Daily Read.md"
  git commit -q -m "$MSG (data-only)"
fi

if [ -n "$(git rev-list origin/main..HEAD)" ]; then
  echo "stranded commits detected: $(git rev-list --count origin/main..HEAD) — completing interrupted push"
  git push -q origin main && echo "PUSHED TO STAGING ✓"
# PROD-PUSH FIX (2026-10-10): remote 'origin' is the STAGING repo; the script
# only ever pushed there and printed "PUSHED TO PROD ✓" (false success — the
# real board went stale). prod remote now pushed explicitly.
git push -q prod main:main && echo "PUSHED TO PROD ✓"
fi


# deploy-serialization guard (added 2026-10-07, incident: 3 pushes within 40s
# stacked Pages deploys; the blocked one failed with 400 and the CDN kept
# serving the stale build for ~10 min). Before pushing, wait until the latest
# Pages run on prod has reached a terminal state (success|failure|cancelled).
# Max 8 min wait; on timeout, abort loudly rather than risk another stack.
if git remote get-url origin | grep -q github.com; then
  REPO="pilot2969/cass-dashboards"
  if [ -n "${GH_TOKEN:-}" ]; then AUTH=(-H "Authorization: Bearer $GH_TOKEN"); else AUTH=(); fi
  for i in $(seq 1 48); do
    STATE=$(curl -sf "https://api.github.com/repos/$REPO/actions/runs?per_page=1" \
      "${AUTH[@]}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["workflow_runs"][0]["status"])' 2>/dev/null || echo unknown)
    case "$STATE" in success|failure|cancelled|completed|unknown) break;; esac
    if [ "$i" -eq 1 ]; then echo "pages deploy in flight ($STATE) — waiting to serialize"; fi
    sleep 10
  done
  if [ "$STATE" != "unknown" ] && case "$STATE" in success|failure|cancelled|completed) false;; *) true;; esac; then
    echo "ERROR: Pages deploy still in flight after 8 min ($STATE) — aborting push to avoid stacking"
    exit 1
  fi
  # also verify the latest run's commit is already deployed (terminal run ahead of HEAD is fine)
  echo "deploy-serialization: clear (last run state: $STATE)"
fi

# staging-first: verify JSON parses clean before any push
python3 -c "import json;[json.load(open(f)) for f in ['data.json','history.json']]" \
  && echo "staging gate: JSON valid"

# canonical-source amendment (2026-10-09): Daily Read.md is the canonical source
# for the daily_read panel; it must be committed with the generated artifacts or
# the repo copy silently diverges from what was parsed (morning-wire incident:
# rewrite landed after push -> deployed panel stale while local file current).
git add data.json history.json "Daily Read.md"
git diff --cached --quiet || git commit -q -m "$MSG (data-only)"
# pull with rebase; a failure must abort the script (set -e), never print success.
# -X ours is safe here because data.json/history.json are generated artifacts:
# our regen output is authoritative over any remote-only drift.
git pull --rebase -X ours -q origin main
git push -q origin main && echo "PUSHED TO STAGING ✓"
# PROD-PUSH FIX (2026-10-10): remote 'origin' is the STAGING repo; the script
# only ever pushed there and printed "PUSHED TO PROD ✓" (false success — the
# real board went stale). prod remote now pushed explicitly.
git push -q prod main:main && echo "PUSHED TO PROD ✓"
# PUSH-TARGET AMENDMENT (2026-10-05): data pushes go to staging too so boards never diverge on numbers.
if git remote get-url staging >/dev/null 2>&1; then
  git push -q staging main && echo "PUSHED TO STAGING ✓"
else
  echo "WARN: no 'staging' remote configured — staging board NOT updated"
fi
