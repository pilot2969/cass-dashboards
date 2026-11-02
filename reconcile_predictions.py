#!/usr/bin/env python3
"""Make data.json predictions[] obey /space, and nothing else.

Extracted from sync_data.sh 2026-11-02, because the same reconcile has to run at
two points in the run: before the build, and again AFTER `git pull --rebase`.
That second call is the one that matters. The pull can land a remote data.json
over the regenerated one -- merge direction is easy to get backwards (during a
rebase, -X ours means UPSTREAM wins, not us), and duplicates reappeared twice
today after a "successful" dedupe for exactly that reason.

  --check   exit 1 if data.json is off (duplicates, or fields diverged from
            /space) without writing anything. Used by the gate and post-pull.
"""
import json, os, sys

P = "/space/prediction/"
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.json")
FIELDS = ("card_class", "resolution", "resolution_date", "window_closes",
          "grace_horizon", "grace_locked", "skill_eligible", "public_status",
          "status", "anchor_grade", "anchor_type", "anchor_source",
          "window_opens", "window_basis", "expiry_date", "expiry_basis",
          "tracking_state")
check = "--check" in sys.argv

data = json.load(open(DATA))
preds = data.get("predictions", [])
problems, out = [], []

# 1. DEDUPE. A second writer ("Board refresh from Rool Machine /space export")
#    appends rather than reconciles; merges republished cards two and three times.
seen = {}
for p in preds:
    bn = p.get("basename")
    if not bn:
        raise SystemExit("RECONCILE: prediction with no basename — cannot key it")
    seen.pop(bn, None)
    seen[bn] = p          # last occurrence wins
if len(seen) != len(preds):
    problems.append(f"predictions[] {len(preds)} entries for {len(seen)} cards")

# 2. /space IS AUTHORITATIVE. Resolution-bearing fields are overwritten every run,
#    so a card that resolves in /space cannot keep publishing yesterday's call.
for p in seen.values():
    src = os.path.join(P, (p.get("basename") or "") + ".json")
    if not os.path.exists(src):
        problems.append(f"{p.get('basename')} in data.json but not in /space")
        continue
    o = json.load(open(src))
    for k in FIELDS:
        if k in o:
            if p.get(k) != o[k]:
                problems.append(f"{p['basename']}.{k}: {p.get(k)!r} -> {o[k]!r}")
            p[k] = o[k]
        elif k in p:
            p.pop(k, None)
    if o.get("confidence_score") is not None:
        c = o["confidence_score"]
        c = round(c * 100) if isinstance(c, (int, float)) and 0 < c <= 1 else c
        if p.get("confidence") != c:
            problems.append(f"{p['basename']}.confidence: {p.get('confidence')!r} -> {c!r}")
        p["confidence"] = c

hard = [x for x in problems if " but not in /space" in x]
if check:
    for x in problems[:12]:
        print("  " + x)
    if len(problems) > 12:
        print(f"  ... {len(problems)-12} more")
    print(f"reconcile --check: {len(problems)} divergence(s)")
    sys.exit(1 if problems else 0)

if hard:
    raise SystemExit("PREDICTION RECONCILE FAILED: " + "; ".join(hard))
if problems:
    print(f"reconcile: {len(problems)} change(s) applied from /space")
    for x in problems[:6]:
        print("  " + x)
    data["predictions"] = list(seen.values())
    json.dump(data, open(DATA, "w"), indent=1, ensure_ascii=False)
else:
    print("reconcile: predictions[] already matches /space")
