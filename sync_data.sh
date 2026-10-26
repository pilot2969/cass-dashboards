#!/bin/bash
# CASS dashboard data-layer sync — data-only, prod+staging per PUSH-TARGET AMENDMENT (2026-10-05):
#   card/data updates -> prod + staging simultaneously; design changes -> staging only until approval.
# Usage: ./sync_data.sh ["commit message"]
# 2026-10-14: pushes now stamp ET date+hour (meta.generated_stamped + commit msg). See /space/protocol/push-timestamp-standard.json
set -euo pipefail
cd "$(dirname "$0")"
MSG="${1:-data refresh $(date +%Y-%m-%d): movers + history regenerated from /space}"

python3 - <<'PY'
import json, glob, os, datetime, html

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

# confidence scale normalization (2026-10-23): source objects mix 0-1 fractions
# and 0-100 percentages; site renders round(conf) so a 0.4 prints as 0%.
# Normalize anything <=1 to percent at the data layer.
for _p in data.get("predictions", []):
    _c = _p.get("confidence")
    if isinstance(_c,(int,float)) and _c <= 1:
        _p["confidence"] = round(_c*100)
cards=[json.load(open(f)) for f in glob.glob(P+"*.json") if not f.endswith(".schema.json")]
INTERNAL=[l.strip() for l in open('internal_cards.txt')] if os.path.exists('internal_cards.txt') else []
cards=[c for c in cards if c.get('basename') not in INTERNAL]
md=lambda c: c.get("last_moved") or c.get("date_made") or ""
recent=sorted([c for c in cards if md(c)>=str(datetime.date.today()-datetime.timedelta(days=7))],
              key=md, reverse=True)
movers=[{"time":md(c), "ref":c.get("title",""),
         "change":f"confidence {c.get('confidence_score')} — status {c.get('status')}",
         "trigger":(c.get("evidence_confirmed") or ["—"])[-1][:180]} for c in recent[:10]]
data["movers"]=movers

# keep the Internal Telemetry ledger count in sync with data.json (single source:
# count lives in data.json; the HTML summary is patched, never rebuilt — Rule 27)
import re as _re
_te = "Internal Telemetry.html"
if os.path.exists(_te):
    _txt = open(_te).read()
    _txt = _re.sub(r"recent entries \(\d+ total\)", f"recent entries ({len(data['mget_ledger'])} total)", _txt)
    open(_te, "w").write(_txt)


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
#
# 2026-10-14 AUTO-CONVERTER: evening editions are written as prose reports, but
# the parser needs the standing card layout (DATE:/SUMMARY:/WATCHING: lists,
# marker line, <details> cards). Two evenings running that conversion was a
# manual step; when skipped the panel silently went empty. Convert prose ->
# card format IN PLACE before parsing. Idempotent: files that already carry the
# marker line are left untouched.
import re, html
def _convert_card_stack(txt):
    # 2026-10-17 ROLLING CARD STACK format: individual '### [HH:MM] Title' cards,
    # newest on top, stacked through the day (protocol: daily-read-rolling-edition).
    # Converts to the standing parser layout. Idempotent via the same marker.
    if "### " not in txt:
        return txt, False
    if "<!--parser markers above" in txt:
        # 2026-10-21 HARDENING: marker present but cards below it written as bare
        # '### ' headings (no <details>) -> parser silently yields 0 cards and
        # the board renders only the watch list. Rebuild the whole file from the
        # ### stack; idempotent because <details> files fall through untouched.
        post = txt.split("<!--parser markers above",1)[1].partition("-->")[2]
        if "<details" not in post:
            txt = txt.split("<!--parser markers above",1)[0] + "### " + post
            # fall through to the standard ### rebuild below
        else:
            return txt, False
    head, _, stack = txt.partition("### ")
    # header may sit BELOW the top card in the stacked format: scan the whole text
    m_iso = re.search(r"# The Daily Read(?: — )?(\d{4}-\d{2}-\d{2})", txt) or re.search(r"\d{4}-\d{2}-\d{2}", head)
    m_long = re.search(r"([A-Z][a-z]+ \d{1,2}, \d{4})", head)
    _date = m_iso.group(1) if (m_iso and m_iso.lastindex) else (m_iso.group(0) if m_iso else (datetime.datetime.strptime(m_long.group(1),"%B %d, %Y").date().isoformat() if m_long else "missing - set before publishing"))
    catalyst = re.search(r"Catalyst node: (.+)", txt) or re.search(r"Catalyst node: (.+)", head)
    cards = re.findall(r"### (.*?)\n(.*?)(?=\n### |\n---|\Z)", txt, re.S)
    if not cards:
        return txt, False
    out=["# The Daily Read","","DATE: " + _date]
    if catalyst: out.append("CATALYST: " + catalyst.group(1).strip())
    out+=["SUMMARY:"]
    out+=["- " + title for title,_ in cards]
    out+=["- What we're watching","WATCHING:","- see card stack below","",
          "<!--parser markers above; collapsible cards below-->","**CARD STACK** (newest first)","","---",""]
    for title,body in cards:
        # 2026-10-21 FORMAT LOCK: beats must render as separate paragraphs with
        # bold labels — plain md (**) and bare newlines collapse inside <details>.
        out+=["<details open>",f"<summary>{title}</summary>",""]
        for para in [x.strip() for x in re.split(r"\n\s*\n", body.strip()) if x.strip()]:
            para=re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", para)
            para=re.sub(r"(?<![\\w])\*(?!\s)(.+?)(?<!\s)\*(?!\\w)", r"<i>\1</i>", para)
            out+=["<p>"+para+"</p>",""]
        out+=["</details>",""]
    return "\n".join(out), True

def _convert_prose_daily_read(txt):
    if "<!--parser markers above" in txt:
        return txt, False
    sec = re.split(r"\n## ", txt)
    stories=[]; watch=[]
    for s in sec[1:]:
        lines=s.split("\n"); title=lines[0].strip()
        body="\n".join(lines[1:]).strip()
        if title=="What we're watching":
            watch=[l.strip().lstrip("- ") for l in body.split("\n") if l.strip().startswith("- ")]
            continue
        stories.append((title,body))
    if not stories:
        return txt, False   # not recognizably prose; leave as-is
    summary=[re.split(r" — ",t)[0] for t,_ in stories]
    _iso=re.search(r"\d{4}-\d{2}-\d{2}", txt)
    _long=re.search(r"([A-Z][a-z]+ \d{1,2}, \d{4})", txt)
    _date=_iso.group(0) if _iso else (datetime.datetime.strptime(_long.group(1),"%B %d, %Y").date().isoformat() if _long else "missing — set before publishing")
    out=["# The Daily Read","","DATE: " + _date,"SUMMARY:"]
    out+=[f"- {x}" for x in summary]+["- What we're watching","WATCHING:"]
    out+=[f"- {w}" for w in watch if not w.startswith("*Sources")]
    out+=["","<!--parser markers above; collapsible cards below-->","**IN THIS EDITION**",""]
    out+=[f"- {x}" for x in summary]+["","---",""]
    for t,b in stories:
        out+=["<details>",f"<summary>{t}</summary>","",b,"","</details>",""]
    return "\n".join(out), True

dr={"summary":[], "watching":[]}
txt=""
if os.path.exists("Daily Read.md"):
    txt=open("Daily Read.md").read()
    txt, converted=_convert_card_stack(txt)
    if not converted:
        txt, converted=_convert_prose_daily_read(txt)
    if converted:
        open("Daily Read.md","w").write(txt)
        print("daily read: prose edition auto-converted to card format")
    elif "DATE:" not in txt:
        print("WARN: Daily Read.md has neither card markers nor recognizable prose — daily_read panel will be empty")
    # 2026-10-23 GUARD: <details> cards without the parser-marker line are silently
    # ignored (main parse yields nothing, rollover fallback silently restores an
    # old edition). Fail loudly instead — hit twice 2026-10-22/23.
    elif "<details" in txt and "collapsible cards below-->" not in txt:
        print("FATAL: Daily Read.md has <details> cards but no '<!--parser markers above; collapsible cards below-->' marker line before the first card. Cards will NOT be parsed; add the marker line and re-run.");
        import sys; sys.exit(1)
    m=re.search(r"DATE:\s*(\S+)", txt)
    if m: dr["date"]=m.group(1)
    # 2026-10-12: card edition — lists live between the markers; cards below.
    cut = txt.split("<!--parser markers above; collapsible cards below-->", 1)[0]
    m = re.search(r"SUMMARY:\s*\n(.*?)\nWATCHING:\s*\n(.*)", cut, re.S)
    if m:
        dr["summary"] = [l.strip().lstrip("- ") for l in m.group(1).strip().splitlines() if l.strip()]
        dr["watching"] = [l.strip().lstrip("- ") for l in m.group(2).strip().splitlines() if l.strip() and not l.strip().startswith("*Sources")]  # sources line stays in prose, not the watch list
data["daily_read"]=dr

# daily_read.cards: parse the collapsible <details> cards below the parser
# markers so the board can render per-story cards instead of flat bullets
# (2026-10-12: card format is the standing Daily Read edition layout).
try:
    ctext=txt.split("collapsible cards below-->",1)[1] if "collapsible cards below-->" in txt else ""
    cards=[]
    for block in re.findall(r"<details[^>]*>(.*?)</details>", ctext, re.S):
        sm=re.search(r"<summary>(.*?)</summary>", block, re.S)
        if not sm: continue
        body=block[sm.end():].strip()
        title=html.unescape(re.sub(r"<[^>]+>","",sm.group(1))).strip()
        cards.append({"title":title, "html":body})
    if cards: dr["cards"]=cards
# 2026-10-22 ROLLOVER RETENTION    : after the daily archive resets the rolling
    # file (pre-morning-wire), the board must keep showing the previous edition's
    # cards instead of silently rendering an empty panel. Fall back to the newest
    # dated edition .md (excluding today's rolling file) and parse it the same way.
    if not dr.get("cards"):
        import glob, fnmatch
        eds=sorted(g for g in glob.glob("Daily Read 20*.md")
                   if g != "Daily Read.md")
        if eds:
            ftxt=open(eds[-1], encoding='utf-8').read()
            ftxt,_fc=_convert_card_stack(ftxt)
            if "collapsible cards below-->" in ftxt:
                ftext2 = ftxt
                fcut = ftext2.split("<!--parser markers above; collapsible cards below-->",1)[0]
                fm = re.search(r"DATE:\s*(\S+)", fcut)
                if fm: dr["date"]=fm.group(1)
                fm2 = re.search(r"SUMMARY:\s*\n(.*?)\nWATCHING:\s*\n(.*)", fcut, re.S)
                if fm2:
                    dr["summary"]=[l.strip().lstrip("- ") for l in fm2.group(1).strip().splitlines() if l.strip()]
                    dr["watching"]=[l.strip().lstrip("- ") for l in fm2.group(2).strip().splitlines() if l.strip() and not l.strip().startswith("*Sources")]
                fb_cards=[]
                for block in re.findall(r"<details[^>]*>(.*?)</details>", ftext2, re.S):
                    sm=re.search(r"<summary>(.*?)</summary>", block, re.S)
                    if not sm: continue
                    fb_cards.append({"title":html.unescape(re.sub(r"<[^>]+>","",sm.group(1))).strip(),"html":block[sm.end():].strip()})
                if fb_cards:
                    dr["cards"]=fb_cards
                    print(f"rollover retention: panel restored from {eds[-1]} ({len(fb_cards)} cards)")
except Exception as e:
    print("card parse warn:", e)

# INSTITUTIONAL STRESS STALENESS (protocol 2026-10-14): scores are hand-reviewed
# estimates; the daily sync auto-rolls the age clock. >7d since hand review = the
# dashboard prints a stale flag next to the panel. Sync never rewrites scores.
# 2026-10-26 fix: institutions.json (hand-edited) is the source of truth;
# import it into data.json each run. Sync still never invents scores.
try:
    _src=json.load(open("institutions.json"))
    if _src.get("institutions"):
        data["institutions"]=_src
except Exception as e:
    print("institution import warn:", e)
inst=data.get("institutions",{})
if inst.get("institutions"):
    last=inst.get("reviewed","2026-10-14")
    inst["age_days"]=(datetime.date.today()-datetime.date.fromisoformat(last)).days
    if inst["age_days"]>7:
        print(f"WARNING: institutional stress scores {inst['age_days']}d unreviewed (reviewed {last}). Hand-review due.")

# 2026-10-14 TIMESTAMP STANDARD: every push stamps ET date+hour in meta
# (generated_stamped) and in the commit message, so prod state is auditable
# to the hour without digging through git log.
from zoneinfo import ZoneInfo
_et=_dt.datetime.now(ZoneInfo("America/New_York"))
data["meta"]["generated_stamped"]=_et.strftime("%Y-%m-%dT%H:%M ET")
json.dump(data, open("data.json","w"), indent=1)
print(f"regenerated: {len(movers)} movers, history through {today}, stamped {_et.strftime('%Y-%m-%dT%H:%M ET')}")
PY
MSG="$MSG @ $(TZ=America/New_York date +%H:%M) ET"

# daily read archive: convert the current Daily Read into archive/ and refresh
# the search index (owner feature 2026-10-14). Runs before commit so archive
# files ship with the same push; failure here must not block the data push.
python3 build_archive.py >> archive.log 2>&1 || echo "WARN: archive build failed — see archive.log"

# stranded-commit guard: a prior run can die between commit and push, leaving
# prod stale while a naive "nothing to push" exit looks like success. If local
# is ahead of origin, finish the push regardless of whether THIS run changed data.
# (2026-10-14: the earlier separate "commit if dirty" block was merged into the
# single add/commit below the staging gate — two commit sites meant the first
# could eat changes and the second see a clean tree, confusing the log.)
if [ -n "$(git rev-list origin/main..HEAD)" ]; then
  echo "stranded commits detected: $(git rev-list --count origin/main..HEAD) — completing interrupted push"
fi
# NOTE: actual pushes happen ONCE, in the consolidated block at the bottom
# (2026-10-14 review: this block previously duplicated the staging+prod pushes,
# mislabeled 'PUSHED TO PROD' before the prod push line — removed).


# deploy-serialization guard (added 2026-10-07, incident: 3 pushes within 40s
# stacked Pages deploys; the blocked one failed with 400 and the CDN kept
# serving the stale build for ~10 min). Before pushing, wait until the latest
# Pages run on prod has reached a terminal state (success|failure|cancelled).
# Max 8 min wait; on timeout, abort loudly rather than risk another stack.
# 2026-10-14 amendment: authenticated (fail-loud), and checks PAGES DEPLOYMENTS
# not just workflow runs — the Oct-14 incident was a stuck deployment record
# (0de2032) with NO in-progress workflow, which the run-only guard never saw.
if git remote get-url prod | grep -q github.com; then
  REPO="pilot2969/cass-dashboards"
  TOK=$(git remote get-url prod | sed -n 's|https://[^:]*:\([^@]*\)@.*|\1|p')
  if [ -n "$TOK" ]; then AUTH=(-H "Authorization: Bearer $TOK"); else
    echo "ERROR: no prod token — serialization guard cannot run authenticated"; exit 1; fi
  BLOCKED=""
  for i in $(seq 1 48); do
    RUN=$(curl -sf "https://api.github.com/repos/$REPO/actions/runs?per_page=1" "${AUTH[@]}" | \
      python3 -c 'import json,sys;w=json.load(sys.stdin)["workflow_runs"][0];print(w["status"]+":"+w["head_sha"][:7])' 2>/dev/null || echo ERR)
    # 2026-10-14 amendment v2: Pages deployment records frequently carry ZERO
    # statuses even after a fully successful run (observed 7077079117, 7080383605,
    # 7080599080 — all succeeded, all statuses:0). A bare statusless record is NOT
    # proof of an in-flight deploy. Pending only if the latest deployment has no
    # statuses AND the latest workflow run for that deployment's SHA is not
    # terminal (i.e. run is queued/in_progress, or run predates/sha-mismatch with
    # the deployment created after it started). If the newest run completed, treat
    # the deployment as settled regardless of its status list.
    IN_FLIGHT=$(python3 - "$TOK" <<'PYEOF'
import json,sys,urllib.request
tok=sys.argv[1]
def get(url):
    r=urllib.request.Request(url,headers={"Authorization":"Bearer "+tok,"User-Agent":"sync-guard"})
    return json.load(urllib.request.urlopen(r,timeout=15))
try:
    base="https://api.github.com/repos/pilot2969/cass-dashboards"
    ds=get(base+"/deployments?environment=github-pages&per_page=1")
    wr=get(base+"/actions/runs?per_page=5")
    runs=wr.get("workflow_runs",[])
    if not ds:
        print("no"); sys.exit()
    dep=ds[0]
    depsha=dep["sha"][:7]
    match=[r for r in runs if r["head_sha"][:7]==depsha]
    if not match:
        print("yes"); sys.exit()   # deployment with no matching run -> assume stuck
    state=match[0]["status"]
    print("no" if state in ("success","failure","cancelled","completed") else "yes")
except Exception:
    print("no")  # API hiccup: fail-open rather than deadlocking the sync
PYEOF
    )
    STATE="${RUN%%:*}"
    case "$STATE" in success|failure|cancelled|completed) : ;; *) BLOCKED="$RUN (run)" ;; esac
    [ "$IN_FLIGHT" = yes ] && BLOCKED="$BLOCKED pending-pages-deployment"
    if [ -z "$BLOCKED" ]; then break; fi
    if [ "$i" -eq 1 ]; then echo "pages deploy in flight: $BLOCKED — waiting to serialize"; fi
    sleep 10
  done
  if [ -n "$BLOCKED" ]; then
    echo "ERROR: pages deploy not settled after 8 min ($BLOCKED) — aborting push to avoid stacking."
    echo "Stuck deployment without a running workflow needs manual cancel (browser: repo Settings→Environments→github-pages) or a PAT with deployments scope."
    exit 1
  fi
  echo "deploy-serialization: clear (last run: $RUN)"
fi

# staging-first: verify JSON parses clean before any push
python3 -c "import json;[json.load(open(f)) for f in ['data.json','history.json']]" \
  && echo "staging gate: JSON valid"

# 2026-10-21 HARDENING: the daily_read panel fails SILENT when cards parse to
# zero (md present, board shows watch list only). Assert loudly instead.
python3 -c "
import json,sys,os
raw=open('Daily Read.md',encoding='utf-8').read() if os.path.getsize('Daily Read.md') else ''
rolled_over=(not raw.strip()) or ('DATE:' not in raw and '<details' not in raw and '###' not in raw)
dr=json.load(open('data.json')).get('daily_read') or {}
n=len(dr.get('cards') or [])
print('daily_read cards parsed:',n)
if n==0 and not rolled_over:
    sys.exit('FAIL: daily_read.cards==0 — Daily Read.md has content but parsed no cards; board would render empty panel. Fix the md format before pushing.')
if n==0 and rolled_over:
    print('rolled-over state: rolling file empty pre-morning-wire — retaining previous cards on the board (archive rebuild 2026-10-22)')
"

# canonical-source amendment (2026-10-09): Daily Read.md is the canonical source
# for the daily_read panel; it must be committed with the generated artifacts or
# the repo copy silently diverges from what was parsed (morning-wire incident:
# rewrite landed after push -> deployed panel stale while local file current).
git add data.json history.json "Daily Read.md" Daily\ Read\ 20*.md archive/ archive.html build_archive.py sync_data.sh archive.log
git diff --cached --quiet || git commit -q -m "$MSG (data-only)"
# pull with rebase; a failure must abort the script (set -e), never print success.
# -X ours is safe here because data.json/history.json are generated artifacts:
# our regen output is authoritative over any remote-only drift.
git pull --rebase -X ours -q origin main
# CONSOLIDATED PUSH BLOCK (2026-10-14 review): exactly one push per remote, per
# run. origin = staging repo, prod = prod repo, staging = alias of origin.
# 2026-10-21 PAGES-SERIALIZATION: GitHub Pages rejects a new deployment while
# one is in flight ("in progress deployment" 400). Old behavior: back-to-back
# pushes -> staging deploy always collides -> failure emails with no content
# loss (Cloudflare serves the repo, not Pages). Fix: wait for in-flight runs,
# push prod FIRST, wait for its Pages run to finish, then push staging.
_pages_wait() { _r="$1"; _tok="$2"; _t0=$(date +%s);
  while :; do
    _st=$(curl -s -H "Authorization: token $_tok" \
      "https://api.github.com/repos/$_r/actions/runs?per_page=1&event=push" \
      | jq -r '.workflow_runs[0].status // "none"')
    [ "$_st" = "in_progress" ] || [ "$_st" = "queued" ] || break
    [ $(( $(date +%s) - _t0 )) -ge 420 ] && { echo "  pages-wait: timeout on $_r, pushing anyway"; break; }
    sleep 15
  done; }
_ptok=$(git remote get-url prod | sed 's|https\://[^:]*:\([^@]*\)@.*|\1|')
_pages_wait pilot2969/cass-dashboards-staging "$_ptok"
git push -q origin main && echo "PUSHED TO STAGING (origin) ✓"
_pages_wait pilot2969/cass-dashboards "$_ptok"
git push -q prod main:main && echo "PUSHED TO PROD ✓"
sleep 10
_pages_wait pilot2969/cass-dashboards-staging "$_ptok"
if git remote get-url staging >/dev/null 2>&1; then
  # staging alias already covered by origin push above; push only if it points elsewhere
  [ "$(git remote get-url staging)" = "$(git remote get-url origin)" ] && echo "staging alias == origin (already pushed)" || { git push -q staging main && echo "PUSHED TO STAGING (staging remote) ✓"; }
else
  echo "WARN: no 'staging' remote configured — staging board NOT updated"
fi
# R26a (2026-10-10): after any HTML patch, rg EVERY date-bearing pattern
# ("Updated <b>", "Built", "CASS Briefing —", hero text) — the footer stamp
# and hero Updated line are SEPARATE strings; patching one is not the other.
