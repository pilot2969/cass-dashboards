#!/usr/bin/env python3
"""Section 3 generator — absorption flow readings, derived from /space/absorption.

2026-11-06: the 3.1 rate bars and the 3.2 direction split were hand-set HTML.
`45 / 25 / 17 / 132` was not reproducible from any stored field: `specimen_direction`
is free text (76 nulls, 18 clean values across 8 spellings), so nothing generated it.
This script counts the corpus and emits the panel. Rules are stated, not implied:

  FLANK = the direction the specimen's frame is produced and carried by.
          right     - right-flank actor, page, or recirculator named
          left      - left-flank actor, page, or recirculator named
          mixed     - both flanks named, mirror pair, or explicit reciprocal language
          structure - in-group / loyalty / repair framing, no out-group named

Rule sensitivity is printed with the output, because the honest reading of this
corpus depends on which question you ask. See flank.json["rules"].
"""
import json, glob, os, collections, datetime

SRC = "/space/absorption/*.json"
OUT = "flank.json"
LEGACY = {"right": 45, "mixed": 25, "left": 17, "structure": 132}

def week(d):
    y, w, _ = d.isocalendar()
    return f"W{w:02d}", y

rows = []
for p in sorted(glob.glob(SRC)):
    d = json.load(open(p))
    b = os.path.basename(p)[:-5]
    ds = (d.get("date") or "")[:10]
    try:
        dt = datetime.date.fromisoformat(ds)
    except ValueError:
        continue
    rows.append({"b": b, "d": ds, "wk": week(dt), "flank": d.get("flank") or "uncoded",
                 "theme": d.get("theme") or "other"})

rows.sort(key=lambda r: r["d"])
weeks = collections.Counter()
for r in rows:
    weeks[r["wk"][0]] += 1
order = sorted(weeks, key=lambda w: (int(w[1:]),))
split = collections.Counter(r["flank"] for r in rows)
themes = collections.Counter(r["theme"] for r in rows)
week_split = collections.defaultdict(collections.Counter)
for r in rows:
    week_split[r["wk"][0]][r["flank"]] += 1

partial = rows[-1]["d"] if rows else None
payload = {
    "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "total": len(rows),
    "span": [rows[0]["d"], rows[-1]["d"]] if rows else ["", ""],
    "weeks": [{"wk": w, "n": weeks[w], "split": dict(week_split[w])} for w in order],
    "split": {k: split.get(k, 0) for k in ("right", "left", "mixed", "structure", "uncoded")},
    "coded": sum(v for k, v in split.items() if k in ("right", "left", "mixed")),
    "themes": dict(themes.most_common()),
    "legacy": LEGACY,
    "rules": {
        "flank": "direction the frame is produced and carried by (actor/source basis)",
        "coded": "right + left + mixed; structure specimens name no out-group",
        "sensitivity": "the legacy hand-set split counted only specimens whose own frame is aimed at an out-group; this generator counts every specimen a flank produced or carried, so structure specimens shrink and right rises. Neither number is wrong; they answer different questions. Target-based coding needs the dehumanization_frame flag repaired first (78 true / 141 false in corpus, inconsistent).",
    },
}
json.dump(payload, open(OUT, "w"), indent=1)

data = json.load(open("data.json"))
data["flank"] = payload
json.dump(data, open("data.json", "w"), indent=1)

print(f"flank.json: {len(rows)} specimens, {order[0]}..{order[-1]}")
print("weeks:", ", ".join(f"{w}={weeks[w]}" for w in order))
print("split:", dict(payload["split"]), "coded", payload["coded"])
print("legacy:", LEGACY)
