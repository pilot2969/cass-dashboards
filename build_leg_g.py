#!/usr/bin/env python3
"""Leg G — legitimation flow. Generated from /space/legitimation_event.

Why this exists: the board carried G as a BLIND SPOT ("no dated population of
institutional-refusal events exists") while /space/legitimation_event had been
filling since 2026-09-04 with a closed taxonomy. That is the same defect v4.15
fixed for E: a leg printing a score with no series behind it.

What it can and cannot say is printed with the numbers, never left to the reader:
  - the collection starts 2026-09-04, so there is no pre-window baseline;
  - counts are what the machine recorded, not what happened;
  - journal volume is the recording control and it moved in November;
  - the two external series (court rulings per month, federal-official
    resignations per month) still do not exist in the record.
"""
import json, glob, os, datetime, collections, subprocess

SRC = "/space/legitimation_event"
JOURNAL = "/space/journal"
OUT = "leg_g.json"

rows = []
for f in glob.glob(SRC + "/*.json"):
    d = json.load(open(f))
    d["_basename"] = os.path.basename(f)[:-5]
    rows.append(d)
rows.sort(key=lambda r: (r.get("date", ""), r["_basename"]))

def month(d): return (d or "")[:7]

jcount = collections.Counter()
for f in glob.glob(JOURNAL + "/*.json"):
    d = json.load(open(f))
    dt = d.get("date") or d.get("created")
    if dt and len(str(dt)) >= 7:
        jcount[str(dt)[:7]] += 1

def days_in(m, end):
    y, mm = int(m[:4]), int(m[5:7])
    nxt = datetime.date(y + (mm == 12), 1 if mm == 12 else mm + 1, 1)
    start = datetime.date(y, mm, 1)
    return max(1, (min(nxt, end) - start).days)

end = max(datetime.date.fromisoformat(max(r["date"] for r in rows)), datetime.date.today())
series = []
for m in sorted({month(r["date"]) for r in rows}):
    w = [r for r in rows if month(r["date"]) == m and r.get("direction") == "withdraw"]
    g = [r for r in rows if month(r["date"]) == m and r.get("direction") == "grant"]
    dj = jcount.get(m, 0)
    series.append({
        "month": m,
        "withdrawals": len(w),
        "grants": len(g),
        "weighted": round(sum(float(r.get("significance") or 0) for r in w), 1),
        "journal": dj,
        "per_100_journal": round(len(w) / dj * 100, 1) if dj else None,
        "days_covered": days_in(m, end),
    })

comp = collections.Counter((r.get("institution", "?"), r.get("event_type", "?")) for r in rows if r.get("direction") == "withdraw")
composition = [{"institution": k[0], "event_type": k[1], "n": v} for k, v in comp.most_common()]

by_inst = collections.Counter(r.get("institution", "?") for r in rows if r.get("direction") == "withdraw")

tot_w = sum(s["withdrawals"] for s in series)
tot_g = sum(s["grants"] for s in series)
span_days = (end - datetime.date.fromisoformat(min(r["date"] for r in rows))).days + 1

payload = {
    "generated": datetime.date.today().isoformat(),
    "generator": "build_leg_g.py",
    "source": SRC,
    "leg": "G",
    "label": "Legitimation flow",
    "reading": "dated institutional withdrawals of standing, counted from a closed taxonomy",
    "window": {"start": min(r["date"] for r in rows), "end": end.isoformat(), "days": span_days},
    "totals": {
        "withdrawals": tot_w, "grants": tot_g, "weighted": round(sum(float(r.get("significance") or 0) for r in rows if r.get("direction") == "withdraw"), 1),
        "per_month": round(tot_w / (span_days / 30.44), 1),
        "events_total": len(rows),
    },
    "series": series,
    "composition": composition,
    "by_institution": [{"institution": k, "n": v} for k, v in by_inst.most_common()],
    "control": {
        "label": "journal volume",
        "note": "the machine's own recording rate, not the population rate",
        "november_break": "journal entries fell from ~6.0/day (Sep–Oct) to 1.9/day (Nov 1–9), so per-100 rates are inflated for November and must not be read as a rise in refusals",
    },
    "disclosers": [
        "The collection starts 2026-09-04. Two months of history is a level, not a trend, and no baseline exists before it — nothing here says refusals are rising.",
        "Counts are what was recorded, not what happened. A week with no entry may be a quiet week or an unread one.",
        "Court rulings are the bulk of it because courts issue dated, published acts. Resignations and credentialing-body acts are undercounted by construction: they are harder to see and are only in the record when a reporter or an official states them.",
        "Grants (a court reversing itself, an institution restoring standing) are counted separately as the counter-series. One is on record. One counter-event is not a rate.",
        "The version the board said it needed — two independent external series, court rulings against the executive per month and federal-official resignations per month — still does not exist here. This series is internal: one sampler, one taxonomy, no outside check.",
    ],
    "status": "INTERNAL SERIES · no external validation",
}

json.dump(payload, open(OUT, "w"), indent=1)
print(f"leg_g: {tot_w} withdrawals / {tot_g} grants over {span_days}d from {len(rows)} events → {OUT}")
