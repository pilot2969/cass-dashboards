#!/bin/bash
# CASS dashboard data-layer sync — data-only, prod+staging per PUSH-TARGET AMENDMENT (2026-10-05):
#   card/data updates -> prod + staging simultaneously; design changes -> staging only until approval.
# Usage: ./sync_data.sh ["commit message"]
# 2026-10-14: pushes now stamp ET date+hour (meta.generated_stamped + commit msg). See /space/protocol/push-timestamp-standard.json
set -euo pipefail
cd "$(dirname "$0")"
MSG="${1:-data refresh $(date +%Y-%m-%d): movers + history regenerated from /space}"

python3 - <<'PY'
import json, glob, os, datetime, html, collections as _collections, subprocess as _sp

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

# predictions[] RECONCILIATION (2026-11-02). Three incidents in one day, one root
# cause: predictions[] is a hand-carried snapshot, so a card that changes in /space
# keeps publishing yesterday's resolution. The register was rebuilt from /space and
# read correct while data.json still said resolution=holding.
# DEDUPE is the second half of it: a second writer ("Board refresh from Rool Machine
# /space export") APPENDS rather than reconciles, so merges republish cards two and
# three times over. Live data.json carried 81 entries for 69 cards.
# Both now live in reconcile_predictions.py so the SAME reconcile can run again after
# `git pull --rebase` — that second call is the one that actually holds, because the
# pull can land a remote data.json over the regenerated one.
import subprocess
_rp=subprocess.run(["python3","reconcile_predictions.py"],capture_output=True,text=True)
print(_rp.stdout.strip() or _rp.stderr.strip())
if _rp.returncode!=0:
    raise SystemExit("PREDICTION RECONCILE FAILED:\n"+_rp.stdout+_rp.stderr)
data=json.load(open("data.json"))   # re-read: the reconcile calls in from disk
cards=[json.load(open(f)) for f in glob.glob(P+"*.json") if not f.endswith(".schema.json")]
INTERNAL=[l.strip() for l in open('internal_cards.txt')] if os.path.exists('internal_cards.txt') else []
cards=[c for c in cards if c.get('basename') not in INTERNAL]
md=lambda c: c.get("last_moved") or c.get("date_made") or ""
recent=sorted([c for c in cards if md(c)>=str(datetime.date.today()-datetime.timedelta(days=7))],
              key=md, reverse=True)
def _pct(v):
    # 2026-11-02: movers printed raw scores, so a 0-1 card rendered "confidence 0.07".
    # Normalize here as well as in predictions[] above.
    if isinstance(v,(int,float)) and 0 < v <= 1: return round(v*100)
    if isinstance(v,float) and v.is_integer(): return int(v)   # 20.0 -> 20
    return v
movers=[{"time":md(c), "ref":c.get("title",""),
         "change":f"confidence {_pct(c.get('confidence_score'))} — status {c.get('status')}",
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

# REGISTER DRIFT GUARD (2026-11-02, rebuilt 2026-11-02 14:05 ET): the public
# forecast register in Internal Telemetry.html is baked, not rendered from
# data.json, so a card that moves in /space does not move on the page until the
# register is regenerated. Found live on 2026-11-02: 14 cards displaying stale
# percentages (three showed 0% — a 0-1 confidence scale artifact) and 14 scored
# predictions absent entirely.
# REBUILD NOTE: the first version of this guard matched titles with a loose
# span regex and a 45-char key, which both missed real absence and flagged
# present cards. It now parses the register the same way a reader sees it
# (<summary> row -> first <span> title, nearest NN%), then matches live cards
# to page cards by best similarity, so the report is a true absent/stale list.
try:
    import re as _r2, glob as _g2, json as _j2, os as _o2, difflib as _d2, html as _ht2
    _tp="Internal Telemetry.html"
    if _o2.path.exists(_tp):
        _h=open(_tp,encoding='utf-8').read()
        _blk=_h[_h.find("What we're tracking"):_h.find("Technical Information")]
        # 2026-11-02: match on data-card basename, exact. Fuzzy title matching both
        # directions produced false drift (two Korea cards paired to the same row).
        _page={}
        for _m in _r2.finditer(r'<details class=evt data-card="([^"]+)">(.*?)</summary>',_blk,_r2.S):
            # pill only: the first "%" in a card can be in its title ("scored at 7%
            # through 2030"), which produced phantom stale-pct alarms.
            _pc=_r2.search(r'class="z35 [^"]*">[^<]*?(\d+)%',_m.group(2))
            if _pc: _page[_m.group(1)]=int(_pc.group(1))
        _internal=set()
        if _o2.path.exists("internal_cards.txt"):
            _internal={l.strip() for l in open("internal_cards.txt") if l.strip()}
        # v3.11.1 (2026-11-04): the register used to be baked into the page, so this check
        # parsed HTML for per-card percentages. Since the register renders live from
        # data.json, the baked marks are only the handful of hand-picked Big Questions —
        # so all 83 scored cards read as "off-register" on every run. A WARN that fires when
        # nothing is wrong trains the reader to ignore the one that matters. Compare against
        # data.json.predictions (the actual rendering source) and keep the HTML as fallback.
        try:
            _dp=_j2.load(open("data.json"))
            _page={e["basename"]:int(round(float(e.get("confidence_score") or e.get("confidence") or 0)))
                   for e in _dp.get("predictions",[]) if e.get("basename")}
            _src="data.json"
        except Exception:
            _src="page HTML"
        _absent=[]; _stale=[]
        for _f in sorted(_g2.glob("/space/prediction/*.json")):
            if _f.endswith(".schema.json"): continue
            _bn=_o2.path.basename(_f)[:-5]
            if _bn in _internal: continue
            _o=_j2.load(open(_f)); _c=_o.get("confidence_score")
            if _c is None: continue
            if isinstance(_c,(int,float)) and 0<_c<=1: _c=_c*100
            _c=int(round(float(_c)))
            _t=_o.get("title") or _bn
            if _bn not in _page:
                _absent.append((_t,_c,_o.get("status"),_bn))
            elif abs(_page[_bn]-_c)>=2:
                _stale.append((_t,_page[_bn],_c,_bn))
        if _stale or _absent:
            print(f"WARNING: register drift vs {_src} — {len(_stale)} card(s) show a stale pct, {len(_absent)} scored card(s) off-register.")
            for _t,_pp,_lv,_pt in sorted(_stale,key=lambda x:-abs(x[2]-x[1]))[:15]:
                print(f"  pct {_pp:>3}% -> live {_lv:>3}%  {_t[:70]}")
            for _t,_c,_st,_bn in sorted(_absent,key=lambda x:-x[1]):
                print(f"  off-register: {_c:>3}% [{_st}] {_t[:70]}")
            print(f"  register holds {len(_page)} cards.")
except Exception as _e:
    print("register drift check warn:", _e)

# CADENCE COUNTS + BAKED-FIGURE GUARD (2026-11-02): the counts row under the
# gauge panel (items logged today / tracked predictions / claims tested) was baked
# at 11 / 64 / 25 while the register and tribunal had moved to 1 / 64 / 28 — the
# row read stale under a hard refresh because it was HTML, not data. Sync now
# emits data.counts each run, which the page renders live (ids zc-items,
# zc-preds, zc-claims). Baked fallbacks in the HTML are updated to match.
# Guard also checks the heading and per-section forecast counts against the cards
# actually present, so "64 forecasts" can never silently disagree with the page.
try:
    _cnt={}
    _et_today=(datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-4)))).date().isoformat()
    # ET, not UTC: the box runs UTC, so date.today() flips to tomorrow at 20:00 ET and the
    # board read "0 logged today" for every item logged this evening (2026-11-05).
    _cnt["items_today"]=sum(1 for _e in data.get("mget_ledger",[]) if str(_e.get("date",""))[:10]==_et_today)
    _cnt["tracked_predictions"]=len(data.get("predictions",[]))
    _decided={"sustained","revised","overturned","held-for-revision"}
    _cnt["claims_tested"]=sum(1 for _f in _g2.glob("/space/gauntlet/*.json")
        if not _f.endswith(".schema.json") and str(_j2.load(open(_f)).get("verdict") or "").lower() in _decided)
    _cnt["unscored_predictions"]=sum(1 for _p in data.get("predictions",[]) if _p.get("confidence") is None)
    data["counts"]=_cnt
    print(f"counts: {_cnt['items_today']} logged today · {_cnt['tracked_predictions']} tracked · {_cnt['claims_tested']} claims tested")
    if _o2.path.exists("Internal Telemetry.html"):
        _h2=open("Internal Telemetry.html",encoding="utf-8").read()
        _reg=_h2[_h2.find("What we're tracking"):_h2.find("Technical Information")]
        # 2026-11-02: counted <summary> tags, so the "Resolving next 45 days" group
        # summary scored as a card and the guard cried 70 vs 69 forever. Count cards.
        _cards=len(_r2.findall(r"<details class=evt",_reg))
        _heads=[int(x) for x in _r2.findall(r"<span class=mut>([0-9]+) forecasts</span>",_reg)]
        _says=sum(_heads)
        if _says!=_cards:
            print(f"WARNING: section forecast counts say {_says}, page holds {_cards} cards. Regenerate the register or fix the headers.")
        for _id,_v in (("zc-items",_cnt["items_today"]),("zc-preds",_cnt["tracked_predictions"]),("zc-claims",_cnt["claims_tested"])):
            _m=_r2.search(r'id="%s">([0-9]+)<'%_id,_h2)
            if _m and int(_m.group(1))!=_v:
                # 2026-11-02: this used to warn and leave a stale baked default, so a
                # failed fetch rendered a number that was true two days ago. Stamp it.
                print(f"baked fallback {_id}: {_m.group(1)} -> {_v}")
                # 2026-11-02: this call was written as sub(pattern, string, count=1),
                # so it raised TypeError every run and the handler above swallowed it —
                # the baked fallback was reported as "stamped" while never changing.
                # And the pattern was built from the NEW value, so it could never match.
                # Match the old digits, replace with the new ones.
                _h2=_r2.sub(r'(id="%s">)\s*\d+(<)'%_id, r'\g<1>%d\g<2>'%_v, _h2, count=1)
        open("Internal Telemetry.html","w",encoding="utf-8").write(_h2)
    _m2=_r2.search(r"Last review: <span id=\"zinst-reviewed\">",_h2)
    if not _m2:
        print("WARNING: gauges panel is missing its live review-date hook (zinst-reviewed); the staleness clock cannot render.")
except Exception as _e:
    print("counts/guard warn:", _e)

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
# MGET MODEL STATE (2026-11-04): mget_state.json (hand-edited) is the source of
# truth for the four leg dials. sync NEVER rewrites a dial; it imports the file
# and derives the two derived rows itself, from /space: register load per leg
# (the leg_primary classifier on each card) and the lane distribution (the four
# phase-4 branch cards, which must sum to 100).
try:
    _mg=json.load(open("mget_state.json"))
    _load={}; _tot=0
    for _f in glob.glob(P+"*.json"):
        _d=json.load(open(_f)); _l=_d.get("leg_primary")
        if not _l: continue
        _tot+=1; _load[_l]=_load.get(_l,0)+1
    _mg["register_load"]={"total":_tot,"by_leg":_load}
    _missing=[_l["letter"] for _l in _mg.get("legs",[]) if _l["letter"] not in _load]
    if _missing:
        print(f"WARNING: leg(s) with no cards filed: {_missing}")
    # G is not hand-set. It is the mean of the institutional dials, computed here
    # so the two panels cannot disagree — the panel says so, and this makes it true.
    _il=(data.get("institutions") or {}).get("institutions") or []
    if _il:
        _g=round(sum(float(i.get("score") or 0) for i in _il)/len(_il))
        for _l in _mg.get("legs",[]):
            if _l["letter"]=="G":
                _l["score"]=_g
                _l["derive"]=(f"Derived, not hand-set: the mean of the {len(_il)} institutional "
                    "dials above, computed at sync. Moves only when they move.")
    _rv=_mg.get("reviewed")
    if _rv:
        try: _mg["age_days"]=(datetime.date.today()-datetime.date.fromisoformat(_rv)).days
        except Exception: pass
    _lanes=[]
    for _b in ("phase4-branch-acute-crisis","phase4-branch-regime-concedes",
               "phase4-branch-regime-holds-contested","phase4-branch-external-war-diversion"):
        _p=P+_b+".json"
        if not os.path.exists(_p): continue
        _d=json.load(open(_p))
        _lanes.append({"basename":_b,"title":_d.get("title",""),
                       "p":_d.get("confidence_score"),
                       "resolution":_d.get("resolution"),
                       "closes":_d.get("window_closes")})
    if _lanes:
        _sum=round(sum(l["p"] or 0 for l in _lanes),1)
        if abs(_sum-100)>0.5:
            print(f"WARNING: lane cards sum to {_sum}, not 100 — distribution is not a partition.")
        _mg["lanes"]={"sum":_sum,"items":_lanes}
    data["mget"]=_mg
except Exception as e:
    print("mget import warn:", e)

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
# 2026-11-07: "generated" (the data-layer date, distinct from generated_stamped)
# was inherited from whatever data.json sat in the tree — it drifted to 2026-11-05 and
# tripped data.generated (data.json stamped 3d behind today). It is derived here, always.
# 2026-11-07 Q5 HOVER TERMS: the tooltip copy is generated from /space/term, one object
# per term, so a tooltip cannot drift from its source. No term copy is typed into the page.
try:
    _terms={}
    for _f in glob.glob("/space/term/*.json"):
        _t=json.load(open(_f))
        if _t.get("status")=="retired": continue
        _terms[os.path.basename(_f)[:-5]]={"label":_t["label"],"copy":_t["copy"],"units":_t["units"],"source":_t["source"]}
    data["terms"]=_terms
    print(f"terms: {len(_terms)} generated from /space/term")
except Exception as e:
    print("terms import warn:", e)

# 2026-11-09 E-LEG FLOW PANEL: the panel was hand-built on 2026-11-07 and went stale
# within two days — a derived number that was not derived at build time. build_flow_panel.py
# now regenerates it from /space/repression_event INSIDE the export, so the panel cannot be
# older than the data layer it sits in. It refuses to infer double-codings: declared pairs
# are listed in the script, and a same-date pair with different event_type is reported as a
# review candidate in integrity.same_date_review rather than silently merged.
try:
    _sp.run(["python3","build_flow_panel.py"],check=True,capture_output=True)
    data["flow_panel"]=json.load(open("flow_panel.json"))
    _fp=data["flow_panel"]["integrity"]
    print("flow_panel: %d dated events, %d merged, %d undated, %d review candidate(s)" % (
        _fp["unique_dated"],len(_fp["merged_pairs"]),len(_fp["undated_excluded"]),len(_fp["same_date_review"])))
except Exception as e:
    print("WARN flow_panel:", e)

# 2026-11-09 LEG G: the blind spot becomes a counted series. Generated by build_leg_g.py
# from /space/legitimation_event. The board may say the series is thin; it may no longer
# say no series exists.
try:
    _sp.run(["python3","build_leg_g.py"],check=True,capture_output=True)
    data["leg_g"]=json.load(open("leg_g.json"))
    print("leg_g: %d withdrawals over %s" % (data["leg_g"]["totals"]["withdrawals"], data["leg_g"]["window"]["start"]))
except Exception as e:
    print("WARN leg_g:", e)

# 2026-11-09 THRESHOLD WATCH: every active watch carries a stated expiry (Rule 1).
# An active watch with no expiry, or one past its own date, is printed as a defect,
# not smoothed over: that was 20 stale signals before the 11-09 pass.
try:
    _wtoday=_et.date()
    _wrows=[]
    for _f in glob.glob("/space/watch/*.json"):
        _o=json.load(open(_f))
        _ex=_o.get("expire") or ""
        _left=None
        if _ex:
            try: _left=(_dt.date.fromisoformat(_ex)-_wtoday).days
            except Exception: _left=None
        _wrows.append({"title":_o.get("title",""),"added":_o.get("added",""),
            "expire":_ex,"days_left":_left,"priority":_o.get("priority",""),
            "status":_o.get("status",""),"check":(_o.get("check") or "")[:700],
            "action":(_o.get("action_on_trigger") or "")[:700]})
    _wc=_collections.Counter(r["status"] for r in _wrows)
    _act=[r for r in _wrows if r["status"]=="active"]
    _act.sort(key=lambda r:(r["expire"] or "9999-12-31", r["title"]))
    data["watch"]={
        "generated":_wtoday.isoformat(),
        "counts":{"active":len(_act),"fired":_wc.get("fired",0),"expired":_wc.get("expired",0),
                  "retired":_wc.get("retired",0),
                  "active_no_expiry":sum(1 for r in _act if not r["expire"]),
                  "active_past_expiry":sum(1 for r in _act if r["days_left"] is not None and r["days_left"]<0),
                  "high_open":sum(1 for r in _act if r["priority"]=="high")},
        "next":_act[0]["expire"] if _act else None,
        "next_days":_act[0]["days_left"] if _act else None,
        "rows":_act,
        "high":[r for r in _act if r["priority"]=="high"][:8],
    }
    print("watch: %d active, next expiry %s" % (len(_act), data["watch"]["next"]))
except Exception as e:
    print("WARN watch:", e)

data["meta"]["generated"]=_et.date().isoformat()
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

# WIRE-FILED-BUT-NOT-CARDED GUARD (2026-11-10). Two consecutive wire runs wrote a
# standalone "Morning/Evening Wire YYYY-MM-DD.md" and never prepended cards to the
# rolling stack: 11-09 evening, and 11-10 morning. The boards shipped with the
# previous day's cards, the dailyread.live check passed (0 cards vs 0 parsed), and
# nothing failed — the work existed as a file nobody publishes.
# A wire run is not done until its stories are cards. If a wire file for a date is
# newer than the card stack, the cards were not written: fail loudly.
_TODAY=$(TZ=America/New_York date +%F)
for _wf in "Morning Wire $_TODAY.md" "Evening Wire $_TODAY.md"; do
  if [ -f "$_wf" ] && [ "$_wf" -nt "Daily Read.md" ]; then
    echo "FAIL: $_wf was filed but Daily Read.md has not been updated since. A wire run that is not prepended as cards is not published."
    echo "      Write the cards into Daily Read.md (five beats, public voice) and re-run."
    exit 1
  fi
done

# canonical-source amendment (2026-10-09): Daily Read.md is the canonical source
# for the daily_read panel; it must be committed with the generated artifacts or
# the repo copy silently diverges from what was parsed (morning-wire incident:
# rewrite landed after push -> deployed panel stale while local file current).
git add data.json history.json "Daily Read.md" Daily\ Read\ 20*.md archive/ archive.html build_archive.py sync_data.sh verify_prod.js archive.log "Internal Telemetry.html" institutions.json mget_state.json internal_cards.txt
# v3.11.1: the commit trailer asserted "(data-only)" on every run, including releases
# that changed the footer version and the dictionary — a label that contradicts the
# artifact it sits on. Derive it from the tree: shell/dictionary/README changed = release.
if git diff --cached --name-only | grep -qE '^(Internal Telemetry\.html|index\.html|command\.html|archive\.html|README\.md|CHANGELOG\.md|style\.css|verify_prod\.js|sync_data\.sh|mget_state\.json|institutions\.json)$'; then
  _KIND="release"
else
  _KIND="data-only"
fi
git diff --cached --quiet || git commit -q -m "$MSG ($_KIND)"
# 2026-10-26 FIX: the sync itself rewrites Internal Telemetry.html (ledger count)
# but the file was absent from the add list, leaving the tree dirty -> the rebase
# below aborted with "cannot pull with rebase: You have unstaged changes" on every
# run where the ledger count changed (silent: content committed locally, never
# pushed). Sweep stragglers, and autostash as belt-and-braces.
git add -A

# 2026-11-02 FULL-SURFACE GATE (protocol: prod-review-gate). One command, every push.
# Render-verifies all four pages in jsdom against the real data layer, then checks
# canonical /space sources. A FAIL here blocks the commit+push: the board cannot
# ship with a stale ledger, an undated edition, a dead panel, or a leaky token.
# Overridable only deliberately: SKIP_GATE=1 (and the skip is printed).
if [ "${SKIP_GATE:-0}" = "1" ]; then
  echo "GATE SKIPPED BY SKIP_GATE=1 — the push is unverified and must not be called done"
else
  node verify_prod.js --mode=prepush || {
    echo "GATE FAILED — push aborted. Fix every FAIL line above; WARNs are advisory."
    echo "Re-run alone with: node verify_prod.js --mode=prepush"
    exit 1; }
fi

# pull with rebase; a failure must abort the script (set -e), never print success.
#
# 2026-11-02 GENERATED FILES ARE NEVER MERGED. Two things went wrong here today:
#   (a) -X ours during a REBASE means the branch we are rebasing ONTO wins, i.e. the
#       REMOTE data.json beats our regeneration — backwards, and how 81 entries for
#       69 cards reached the live site twice after a dedupe that reported success.
#   (b) Direction is not the real fix. A JSON file merged hunk-by-hunk can end up
#       with neither version's shape: the pull produced a data.json that had lost
#       `counts` and `institutions` entirely, because the remote writer never emits
#       them and a merge is not a rebase of one file's contents.
# So the generated artifacts are snapshotted before the pull and restored after it.
# The remote may own commits; it does not own these files.
GEN="data.json history.json Internal Telemetry.html Daily Read.md archive.html"

# Generated-file snapshot/restore as FUNCTIONS (2026-11-02, second pass). The first
# version inlined this around the origin pull and missed the prod rebase — which is
# where the damage actually happened every time: `git rebase -X ours prod/main`
# during a rebase means the ONTO side wins, so the other writer's data.json (717
# ledger entries, duplicate basenames) and its unscrubbed page replaced ours AFTER
# the pre-push gate had already gone green. Prepush passed, prod served the other
# writer's build, postdeploy failed. Three runs in a row. Both pulls now restore.
_gen_snap() { for _g in $GEN; do [ -f "$_g" ] && cp "$_g" "/tmp/_gen_$(echo $_g | tr ' ' '_')"; done; }
_gen_restore() { for _g in $GEN; do _s="/tmp/_gen_$(echo $_g | tr ' ' '_')"; [ -f "$_s" ] && cp "$_s" "$_g"; done; true; }

# One re-assert, used after EVERY pull. Order is the whole point: restore our
# generated artifacts, re-derive them from /space, scrub the prose, then re-gate.
_reassert() {
  _gen_restore
  if ! python3 reconcile_predictions.py --check >/tmp/_recon.txt 2>&1; then
    echo "POST-PULL: data.json diverged from /space — re-asserting"
    sed -n '1,6p' /tmp/_recon.txt
    python3 reconcile_predictions.py
    python3 build_register.py
  fi
  # FINAL SCRUB: published prose must never carry the board's internal card keys.
  # The renderer scrubs what it builds, but the legacy deep-dive blocks under the
  # big-questions cards were baked long before the renderer and nothing regenerates
  # them, so the token reappeared after the file had already been cleaned once.
  python3 scrub_internal_keys.py
  python3 scrub_internal_keys.py --check || { echo "GATE: internal card keys still in published prose — refusing to push"; exit 1; }
  git add -A && { git diff --cached --quiet || git commit -q --amend --no-edit; }
  # the gate runs LAST, on the tree that will actually be pushed
  node verify_prod.js --mode=prepush || {
    echo "GATE FAILED after pull — push aborted. Fix every FAIL line above."
    exit 1; }
}

_gen_snap
git pull --rebase --autostash -X theirs -q origin main
_reassert
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
# 2026-11-04: the push-target amendment (2026-10-05) has said "design changes ->
# staging only until approval" since it was written, but nothing implemented it —
# every run pushed prod unconditionally. STAGING_ONLY=1 is that missing switch.
if [ "${STAGING_ONLY:-0}" = "1" ]; then
  echo "STAGING_ONLY=1 — prod push SKIPPED (design change awaiting approval)"
else
_pages_wait pilot2969/cass-dashboards "$_ptok"
# 2026-11-02: deploy-cass.sh pushes to the same prod repo, so a bare push here
# gets rejected (fetch first) and the run dies after staging already moved.
if ! git push -q prod main:main 2>/dev/null; then
  _gen_snap
  git fetch -q prod main
  # -X theirs: during a rebase "theirs" is the commit being replayed — ours. The old
  # -X ours handed the remote writer every conflict, which is how its data.json and
  # its stale page kept winning after our gate had passed.
  git rebase --autostash -X theirs prod/main -q || { git rebase --abort; echo "ERROR: prod rebase failed"; }
  _reassert
  git push -q prod main:main && echo "PUSHED TO PROD ✓ (rebased over deploy commit)"
else echo "PUSHED TO PROD ✓"; fi
fi  # end STAGING_ONLY guard
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

# 2026-11-02 POST-DEPLOY GATE (protocol: prod-review-gate). The pre-push gate proves
# the BUILD is sound; this proves the DEPLOY is serving it. GitHub Pages can accept a
# push and still serve the previous artifact, and Cloudflare sits in front of the
# staging URL. Byte-compare live HTML against local, plus the live counts object.
echo "post-deploy verify: live == local ?"
sleep 20
# 2026-11-04: under STAGING_ONLY=1 the prod push never happened, so a prod
# post-deploy gate can only ever fail — and a gate that always fails stops being
# read. Verify the STAGING site instead; prod parity is checked on the run that
# actually promotes the design change.
if [ "${STAGING_ONLY:-0}" = "1" ]; then
  echo "post-deploy verify (STAGING_ONLY): checking staging, prod intentionally behind"
  if node verify_prod.js --mode=postdeploy --url=https://pilot2969.github.io/cass-dashboards-staging; then
    echo "STAGING GATE GREEN — prod still serving the previous build by design"
  else
    echo "STAGING GATE FAILED — the staging deploy is not serving this build."
    exit 1
  fi
elif ! node verify_prod.js --mode=postdeploy --url=https://pilot2969.github.io/cass-dashboards; then
  echo "POST-DEPLOY GATE FAILED — the repo is pushed but the live site is not serving this build."
  echo "Do not report the board as updated until this passes. Check the Pages workflow, then re-run:"
  echo "  node verify_prod.js --mode=postdeploy --url=https://pilot2969.github.io/cass-dashboards"
  exit 1
fi
echo "POST-DEPLOY VERIFIED ✓ (live bytes == local build)"
