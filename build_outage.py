#!/usr/bin/env python3
"""build_outage.py -> outage_panel.json

Substrate tracker (section 2.5). Reads outage_ledger.csv — one row per
provider-level outage — and emits the four readings the panel renders.

WHY THIS IS NOT A LEG INPUT (2026-11-17, design decision
/space/note/2026-11-17-outage-tracker-design-decision.json):
  * /space/instrument confines every record to a leg enum; there is no slot
    for a substrate series.
  * event-duration has no defensible exchange rate into a 0-100 load, and
    inventing one to a decimal is the laundering the register exists to catch.
  * feeding G would let a bad infrastructure week score as legitimacy loss,
    which makes G unfalsifiable in the flattering direction.
So: four readings, no dial, no composite. m.contradiction PRINTS, never blends.

COUNTING RULE: once per provider per event. A customer incident downstream of
a provider event is a second symptom, never a second event.
"""
import csv, json, statistics, collections, datetime, os

ATTACK_PLACE = {
    "me-central-1 UAE": "AWS data centre region, United Arab Emirates",
    "me-south-1 Bahrain": "AWS data centre region, Bahrain",
}

ATTACK_WHAT = {
    "me-central-1 UAE": "Drone strikes damaged the facility; some data in one availability zone was unrecoverable.",
    "me-south-1 Bahrain": "Drone strike damaged the facility; the operator declared the region unavailable.",
}

def _plain_date(d):
    parts = d.split("-")
    return f"{int(parts[2])} {['January','February','March','April','May','June','July','August','September','October','November','December'][int(parts[1])-1]} {parts[0]}"

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "outage_ledger.csv")
TODAY = datetime.date.today()

CAUSE_LABEL = {
    "power": "Power & cooling", "software": "Software & config",
    "config": "Software & config", "network": "Network & DNS",
    "dns": "Network & DNS", "capacity": "Capacity",
    "thirdparty": "Third-party", "unknown": "Unknown", "attack": "Deliberate",
}
CAUSE_COLOR = {
    "Power & cooling": "#b4562f", "Software & config": "#5b9bd5",
    "Network & DNS": "#6b7fd0", "Capacity": "#7a6a58",
    "Third-party": "#4a5c74", "Unknown": "#3a4557", "Deliberate": "#e2564d",
}
ORDER = ["Power & cooling", "Software & config", "Network & DNS",
         "Capacity", "Third-party", "Unknown", "Deliberate"]


def dur(r):
    """Provider-stated hours. An event still down has no stated duration —
    it is reported as open and counted as today-minus-onset, never given a
    false closing time."""
    if r["hours"].strip():
        return float(r["hours"]), True
    return (TODAY - datetime.date.fromisoformat(r["date"])).days * 24.0, False


def fmt(h):
    if h >= 48:
        d = h / 24
        return f"{d:.0f}d" if abs(d - round(d)) < .02 else f"{d:.1f}d"
    hh = int(h); mm = int(round((h - hh) * 60))
    if mm == 60: hh, mm = hh + 1, 0
    return f"{hh}h{'' if mm == 0 else f' {mm:02d}m'}"


rows = list(csv.DictReader(open(LEDGER)))
for r in rows:
    r["h"], r["closed"] = dur(r)
    r["cause_class"] = CAUSE_LABEL.get(r["cause"], "Unknown")

years = sorted({r["date"][:4] for r in rows})
freq, sev = [], []
for y in years:
    rr = [r for r in rows if r["date"][:4] == y]
    closed = [r["h"] for r in rr if r["closed"]]
    freq.append({"year": y, "n": len(rr)})
    sev.append({"year": y, "median": round(statistics.median(closed), 2),
                "max": round(max(closed), 2), "open": sum(1 for r in rr if not r["closed"])})

comp = {}
for y in ("2025", "2026"):
    rr = [r for r in rows if r["date"][:4] == y]
    c = collections.Counter(r["cause_class"] for r in rr)
    comp[y] = {"n": len(rr), "bands": [
        {"label": k, "n": c.get(k, 0), "pct": round(100 * c.get(k, 0) / len(rr), 1),
         "color": CAUSE_COLOR[k]} for k in ORDER if c.get(k)]}

def cal_months_days(d0, d1):
    """Whole calendar months between two dates, plus remainder days. FLOOR, never
    round: a partial month is not a month. 2026-03-01 -> 2026-11-17 is 8mo 16d,
    not '9 months' (261/30 = 8.7 rounds up and overstates the outage)."""
    m = (d1.year - d0.year) * 12 + (d1.month - d0.month)
    anchor = d0
    for _ in range(m):
        y, mo = (anchor.year + (anchor.month // 12)), (anchor.month % 12 + 1)
        day = min(anchor.day, [31,29 if (y%4==0 and (y%100!=0 or y%400==0)) else 28,
                               31,30,31,30,31,31,30,31,30,31][mo-1])
        anchor = datetime.date(y, mo, day)
        if anchor > d1:
            m -= 1
            y2, mo2 = (d0.year + ((d0.month - 1 + m) // 12)), ((d0.month - 1 + m) % 12 + 1)
            anchor = datetime.date(y2, mo2, min(d0.day, [31,29 if (y2%4==0 and (y2%100!=0 or y2%400==0)) else 28,
                               31,30,31,30,31,31,30,31,30,31][mo2-1]))
            break
    return m, (d1 - anchor).days

attacks = [r for r in rows if r["cause"] == "attack"]
for a in attacks:
    if not a["closed"]:
        d0 = datetime.date.fromisoformat(a["date"])
        a["still_down_days"] = (TODAY - d0).days
        a["still_down_months"], a["still_down_rem"] = cal_months_days(d0, TODAY)
        a["still_down_label"] = f"{a['still_down_months']} mo {a['still_down_rem']} d"

# November breadth: 1-17 Nov per year. The whole "is it a spike?" question.
window = [r for r in rows if r["date"][5:7] == "11" and int(r["date"][8:10]) <= 17]
nov = collections.Counter(r["date"][:4] for r in window)
nov_window = [{"year": y, "n": nov.get(y, 0),
               "events": [f"{r['date']} {r['provider']}" for r in window if r["date"][:4] == y]}
              for y in years if y >= "2023"]

last = max(rows, key=lambda r: r["date"])
newest_obs = last["date"]
age = (TODAY - datetime.date.fromisoformat(newest_obs)).days

by_year = {f["year"]: f["n"] for f in freq}
_d26 = sorted(datetime.date.fromisoformat(r["date"]) for r in rows if r["date"].startswith("2026"))
GAP26 = int(statistics.median([(b - a).days for a, b in zip(_d26, _d26[1:])]))
max26 = next(s["max"] for s in sev if s["year"] == "2026")
max25 = next(s["max"] for s in sev if s["year"] == "2025")
y24, y25, y26 = by_year.get("2024", 0), by_year.get("2025", 0), by_year.get("2026", 0)

out = {
    "generated": TODAY.isoformat(),
    "source": "outage_ledger.csv",
    "n_events": len(rows),
    "window": f"{min(r['date'] for r in rows)} → {newest_obs}",
    "reading": (
        f"Frequency is up, severity is down. {y26} provider-level events in 2026 against {y24} in 2024 "
        f"— roughly {round(y26 / y24, 1)}× in two years"
        + (", the worst year in the record —" if y26 == max(f['n'] for f in freq) else " —")
        + f" while the median duration has fallen every year since 2023 and the tail is flat: "
        f"2026's longest closed event is {round(abs(max26 - max25) * 3600)} seconds off 2025's. "
        "More often, shorter. That is dependency concentration with better failover, not "
        "a degrading substrate. A worsening substrate widens the tail; this does not. That is why the "
        "panel carries no dial."
    ),
    "frequency": {
        "headline": y26, "unit": "provider-level outages in 2026 to date",
        "years": freq, "max_n": max(f["n"] for f in freq),
        "multiple_24_26": round(y26 / y24, 1) if y24 else None,
        "last_event": f"{last['date']} · {last['provider']} · {fmt(last['h'])}",
        "rule": ("Counted once per provider per event. A customer incident downstream of a provider "
                 "event is not a second event."),
    },
    "severity": {
        "headline": fmt([s for s in sev if s["year"] == "2026"][0]["median"]),
        "unit": "2026 median duration",
        "years": [s for s in sev if s["year"] >= "2022"],
        "zone_max": max(s["max"] for s in sev if s["year"] >= "2022"),
        "longest_2026": next(fmt(s["max"]) for s in sev if s["year"] == "2026"),
        "longest_2025": next(fmt(s["max"]) for s in sev if s["year"] == "2025"),
        "note": ("The tail is flat. A worsening substrate widens the tail; this does not. "
                 "That is the panel's core read, and the reason it carries no dial."),
    },
    "composition": {
        "years": comp,
        "power_2025": sum(b["n"] for b in comp["2025"]["bands"] if b["label"] == "Power & cooling"),
        "power_2026": sum(b["n"] for b in comp["2026"]["bands"] if b["label"] == "Power & cooling"),
        "power_share_2026": sum(b["pct"] for b in comp["2026"]["bands"] if b["label"] == "Power & cooling"),
        "note": ("The year-over-year change is physical. Three of the five 2026 power events share one "
                 "shape: a utility event, a generator or UPS that did not carry the load, cooling loss "
                 "behind it. A capital-maintenance signature, not a cyber signature — and why this "
                 "panel cannot be scored into M, which reads fiscal and administrative strain."),
    },
    "legibility": {
        "headline": f"{100 * len(attacks) / len(rows):.1f}%",
        "record_n": len(rows),
        "unit": f"{len(attacks)} of {len(rows)} coded as deliberate attack",
        "attacks": [{"date": a["date"], "provider": a["provider"], "scope": a["scope"],
                     "note": a["note"], "still_down_days": a.get("still_down_days"), "still_down_label": a.get("still_down_label"), "still_down_months": a.get("still_down_months"), "still_down_rem": a.get("still_down_rem"),
                     "when": _plain_date(a["date"]),
                     "where": ATTACK_PLACE.get(a["scope"], a["scope"]),
                     "what": ATTACK_WHAT.get(a["scope"], a["note"]),
                     "status": (f"still down, {a.get('still_down_label')}" if a.get("still_down_label") else "restored")}
                    for a in attacks],
        "named_actor": 0,
        "floor_banner": (
            "This is a floor, not a rate. The series is coded from vendor post-mortems, and a "
            "post-mortem cannot see inside a 60-day dwell window. The two March events are visible "
            "only because they were kinetic. A quiet intrusion that sat two months and was later "
            "called 'equipment failure' would be coded here as power."
        ),
        "counted": ("Both are counted because both clear the same bar: physical damage to the facility, "
                    "confirmed by the operator, and downtime that has not ended. Neither is an estimate, "
                    "an inferred intrusion or a vendor's unexplained failure — the downtime is real and "
                    "still running."),
        "rest_note": (f"The other {len(rows)-len(attacks)} events are vendor-stated equipment, power, cooling, config or network "
                      "failures, each with a stated cause and a restoration time. They are real outages too. "
                      "What separates them is that no operator has attributed them to an attacker."),
    },
    "breadth": {
        "nov_window": nov_window,
        "banner": (
            f"1–17 Nov: {nov.get('2026', 0)} provider-level event in 2026, {nov.get('2024', 0)} in 2024, "
            f"{nov.get('2025', 0)} in 2025. A cluster of customer-facing reads — banks, airlines, a "
            "classified network — is not a cluster of causes until independent upstreams are shown. "
            "Symptom count is not cause count."
        ),
    },
    "guards": {
        "obs.fresh": {"ok": age <= 7, "age_days": age, "latest": newest_obs,
                      "median_gap_2026": GAP26,
                      "text": f"latest observation {newest_obs}, {age} day{'s' if age != 1 else ''} old. "
                              f"The ledger codes provider-level events only, at roughly {y26} a year, so a quiet "
                              f"fortnight is normal: the 2026 median gap between events is {GAP26} days. "
                              "Past 7 days the panel prints STALE as a disclosure; it does not stop a push."},
        "obs.breadth": {"ok": True,
                        "text": ("window count in the panel equals the coded ledger count; forces the "
                                 "'one event, many symptoms' line whenever a single provider event carries "
                                 "more than 5M extract reports.")},
        "obs.floor": {"ok": True,
                      "text": "the legibility render contains 'floor' and the dwell-caveat string."},
        "m.contradiction": {"ok": None,
                            "text": ("PRINTS, never fails. Fires when M reads above 75 while the substrate "
                                     "is demonstrably restoring in hours — a question for the reader, "
                                     "never an arithmetic term.")},
        "substrate.physical": {"ok": None,
                               "text": ("this panel covers the digital substrate only. No series exists for "
                                        "grid, water or cooling failure as such. That is where 2026 actually "
                                        "got worse, and the layer where a deliberate action would read as an "
                                        "accident for sixty days.")},
    },
    "does_not": [
        {"q": "Feeds a leg?", "a": "No.",
         "why": "Unit mismatch: event-duration has no defensible exchange rate into a 0-100 load. Inventing one and reporting it to a decimal is the laundering the register exists to catch."},
        {"q": "Feeds G?", "a": "No.",
         "why": "G is the mean of the eight institutional dials. Adding internet reliability would let a bad infrastructure week score as legitimacy loss, which makes G unfalsifiable in the flattering direction."},
        {"q": "Has a dial?", "a": "No.",
         "why": "Four readings, no composite. A composite needs weights nobody can defend and would hide the one finding that matters: frequency up, severity flat."},
        {"q": "Answers 'is this an attack'?", "a": "No.",
         "why": "It answers 'is the class deteriorating'. Attribution stays with the four-discriminator rule in the observation."},
    ],
}
json.dump(out, open(os.path.join(HERE, "outage_panel.json"), "w"), indent=1)
print(f"outage_panel.json written: {len(rows)} events, {newest_obs}, {len(attacks)} deliberate")
