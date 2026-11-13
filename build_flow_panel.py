#!/usr/bin/env python3
"""E leg — enforcement-capacity flow. Generated from /space/repression_event.

Why this exists: until 2026-11-07 the accumulation-flow card printed four figures
nothing in /space produced. A hand-built flow_panel.json fixed that once and then
went stale in two days, which is the same defect one step later: a derived number
that is not derived at build time. This script is the generator. It runs inside
sync_data.sh, so the panel cannot be older than the export.

Rules it obeys, printed with the numbers rather than left to the reader:
  - dedupe is DECLARED, not inferred. Double-coded pairs are listed by hand; a
    same-date pair with different event_type is reported as a review candidate
    rather than silently merged, because the machine does double-code;
  - undated events are excluded from a monthly series by rule and counted;
  - the control denominator is endogenous (this machine's attention) and is
    printed beside every rate, never divided away;
  - the headline is computed from the series, so it cannot go stale while the
    numbers move.
"""
import json, glob, os, datetime, collections

SRC = "/space/repression_event"
JOURNAL = "/space/journal"
LEDGER = "/space/mget_ledger"
# ET, not UTC: the box runs UTC, so date.today() rolls to tomorrow at 20:00 ET
# and anything stamped in the evening carries tomorrow's date (same fault as
# build_register.py, fixed 2026-11-05; flow/leg_g fixed 2026-11-12).
def _et_today():
    import datetime as _d
    try:
        from zoneinfo import ZoneInfo
        return _d.datetime.now(ZoneInfo("America/New_York")).date()
    except Exception:
        return (_d.datetime.now(_d.timezone(_d.timedelta(hours=-5)))).date()

OUT = "flow_panel.json"

# Declared double-codings: one event, two objects. Keyed by basename.
DEDUPE_PAIRS = [
    ("policy_shift-2026-07-13-national--", "policy_shift-2026-07-13-national--dhs-0",
     "same DHS sensitive-locations rescission, two objects"),
    ("04l3ibikzs74", "2026-09-14-uscis-unlawful-voter-initiative-whistleblower",
     "same DHS/USCIS voter-data whistleblower, two event_type codings"),
]

MONTHS = ["2026-01","2026-02","2026-03","2026-04","2026-05","2026-06",
          "2026-07","2026-08","2026-09","2026-10","2026-11","2026-12"]

def norm_date(s):
    """Accept ISO and the human forms the collection actually uses."""
    s = str(s or "").strip()
    if len(s) >= 10 and s[4] == "-" and s[7] == "-":
        return s[:10]
    for fmt in ("%B %d, %Y", "%b %d, %Y", "%d %B %Y", "%m/%d/%Y"):
        try:
            return datetime.datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            pass
    return None

def count_dir(path):
    c = collections.Counter()
    for f in glob.glob(path + "/*.json"):
        d = json.load(open(f))
        dt = str(d.get("date") or d.get("created") or "")[:10]
        if len(dt) == 10 and dt[4] == "-":
            c[dt[:7]] += 1
    return c

rows, raw_objects = [], 0
for f in glob.glob(SRC + "/*.json"):
    raw_objects += 1
    d = json.load(open(f))
    d["_basename"] = os.path.basename(f)[:-5]
    d["_date"] = norm_date(d.get("date"))
    rows.append(d)

merged, merged_log = set(), []
for a, b, why in DEDUPE_PAIRS:
    if a in {r["_basename"] for r in rows} and b in {r["_basename"] for r in rows}:
        merged.add(b); merged_log.append({"kept": a, "merged": b, "why": why})

kept = [r for r in rows if r["_basename"] not in merged]
undated = [r for r in kept if not r["_date"]]
dated = sorted([r for r in kept if r["_date"]], key=lambda r: (r["_date"], r["_basename"]))

# Same date, different event_type: possible unlisted double-coding. Report, never merge.
bydate = collections.defaultdict(list)
for r in dated:
    bydate[r["_date"]].append(r)
review = [{"date": k, "basenames": [x["_basename"] for x in v], "types": [x.get("event_type") for x in v]}
          for k, v in sorted(bydate.items()) if len({x.get("event_type") for x in v}) > 1]

jcount, lcount = count_dir(JOURNAL), count_dir(LEDGER)
first = min(r["_date"] for r in dated)
end = max(datetime.date.fromisoformat(max(r["_date"] for r in dated)), _et_today())

def days_covered(m, end):
    y, mm = int(m[:4]), int(m[5:7])
    start = datetime.date(y, mm, 1)
    nxt = datetime.date(y + (mm == 12), 1 if mm == 12 else mm + 1, 1)
    return max(1, (min(nxt, end) - start).days)

series = []
for m in sorted({r["_date"][:7] for r in dated}):
    n = sum(1 for r in dated if r["_date"][:7] == m)
    j = jcount.get(m, 0)
    series.append({"month": m, "raw": n,
                   "per_100_journal": round(n / j * 100, 1) if j else None,
                   "journal": j, "ledger": lcount.get(m, 0),
                   "days_covered": days_covered(m, end)})

# Headline computed from the series so it tracks the numbers.
rates = [s for s in series if s["per_100_journal"] is not None]
peak = max(rates, key=lambda s: s["per_100_journal"]) if rates else None
last = series[-1] if series else {}
raw_peak = max(series, key=lambda s: s["raw"]) if series else None
if peak and raw_peak and peak["month"] == raw_peak["month"]:
    headline = (f"Raw and controlled series peak in the same month ({peak['month']}): {peak['raw']} events, "
                f"{peak['per_100_journal']} per 100 journal. The control does not overturn the read here.")
elif peak and raw_peak:
    headline = (f"Raw series peaks in {raw_peak['month']} ({raw_peak['raw']} events); the controlled series "
                f"peaks in {peak['month']} ({peak['per_100_journal']} per 100 journal). Only {peak['month']} "
                f"outruns the recording rate — the rest of the raw movement is the desk going to work.")
else:
    headline = "No month carries both an event count and a recording rate; no controlled read is offered."

comp = collections.Counter(r.get("event_type", "?") for r in dated)
composition = [{"type": k, "n": v} for k, v in comp.most_common()]
kinetic = comp.get("agency_raid", 0)
instrumental = sum(v for k, v in comp.items() if k in ("policy_shift", "surveillance_expansion"))

nspm = sum(1 for r in dated if r.get("nspm7_alignment"))

payload = {
    "generated": _et_today().isoformat(),
    "generator": "build_flow_panel.py",
    "note": ("Every number here is derived from /space at generate time. Nothing is hand-set. "
             "If a series is absent, the panel shows a blind spot, not a filler."),
    "panels": [
        {
            "id": "e-leg-flow", "leg": "E",
            "label": "Enforcement-capacity flow",
            "reading": "recorded state enforcement events per month",
            "series": series,
            "control": {"label": "machine recording rate",
                        "journal_per_month": {s["month"]: s["journal"] for s in series},
                        "note": ("journal volume is this machine's attention, which reacts to the events it "
                                 "records. The denominator is endogenous: neither number is the true one, "
                                 "the pair is the reading.")},
            "headline": headline,
            "disclosers": [
                f"Raw = unique dated events after declared dedupe ({raw_objects} objects, "
                f"{len(merged_log)} pairs merged, {len(undated)} undated excluded = {len(dated)} dated events).",
                "The control denominator is ENDOGENOUS: journal volume is this machine's attention, which reacts to the events it records. Neither number is the true one; the pair is the reading.",
                "Cannot measure capacity, only recorded events. Statutory authority created and never exercised produces no row.",
                f"Left edge ({first}) is a backfill artifact, not a quiet spring.",
                "This is a flow. It cannot move the E-leg stock score from 64.",
            ],
        },
        {
            "id": "e-leg-composition", "leg": "E",
            "label": "Enforcement event composition",
            "reading": f"share of unique dated events by type, {series[0]['month']} to {series[-1]['month']}" if series else "share of unique events by type",
            "series": composition,
            "headline": (f"Kinetic episodic acts are {kinetic} of {len(dated)}. Capacity accumulates through "
                         f"instrument, not through visible coercion: {instrumental} of {len(dated)} events are "
                         f"policy or surveillance."),
            "disclosers": [
                "Robust to the recording-rate problem: a tenfold writing lift does not change which category a written event lands in.",
                "Taxonomy is the collection's own; if it is wrong, this chart is wrong.",
                f"nspm7_alignment is true on {nspm} of {len(dated)} dated events.",
            ],
        },
    ],
    "integrity": {
        "objects": raw_objects,
        "merged_pairs": merged_log,
        "undated_excluded": [{"basename": r["_basename"], "date_raw": r.get("date")} for r in undated],
        "unique_dated": len(dated),
        "same_date_review": review,
        "window": {"start": first, "end": max(r["_date"] for r in dated),
                   "days": (datetime.date.fromisoformat(max(r["_date"] for r in dated)) - datetime.date.fromisoformat(first)).days + 1},
    },
}

json.dump(payload, open(OUT, "w"), indent=1)
print(f"flow_panel: {len(dated)} dated events from {raw_objects} objects "
      f"({len(merged_log)} merged, {len(undated)} undated) · {len(review)} same-date review candidate(s) → {OUT}")
