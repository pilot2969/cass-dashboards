#!/usr/bin/env python3
"""M leg — cost transmission flow. Generated at build time from a cached
public price series, never hand-set.

Why M needed a flow of its own: M is the only leg whose "why" text makes a
claim about a *mechanism* — "cost is now the transmission belt: it arrives in
household budgets before it arrives in any statistic". A stock score cannot
show a transmission belt. A price series can.

Sources are FRED (St. Louis Fed), public domain series:
  DCOILBRENTEU  Brent crude, daily, USD/bbl
  GASREGW       regular retail gasoline, weekly, USD/gal
  GASDESW       diesel retail, weekly, USD/gal

Rules printed with the numbers:
  - the cache is committed (m_flow_cache.json) so a build with no network
    cannot invent a figure, it just dates what it has;
  - every reading is printed with its own observation date, not the build date;
  - the index is a stated weighted average to a stated baseline week, so the
    reader can disagree with the weights rather than with a mystery number;
  - we cannot show a household's budget. We show pump and barrel price, and
    the panel says so.
"""
import json, csv, os, sys, datetime, urllib.request

CACHE = "m_flow_cache.json"
OUT = "m_flow.json"
SERIES = {"brent": "DCOILBRENTEU", "gas": "GASREGW", "diesel": "GASDESW"}
BASE_WEEK = "2026-06-01"      # index = 100 that week
WEIGHTS = {"brent": 0.5, "gas": 0.3, "diesel": 0.2}
SINCE = "2026-05-01"

def fetch():
    cache = {"generated": None, "series": {}}
    for key, sid in SERIES.items():
        url = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=%s" % sid
        raw = urllib.request.urlopen(url, timeout=45).read().decode()
        rows = []
        for r in csv.DictReader(raw.splitlines()):
            d, v = list(r.items())[0][1], list(r.items())[1][1]
            if not d or d.startswith("observation") or v in ("", "."):
                continue
            try:
                rows.append([d, round(float(v), 3)])
            except ValueError:
                pass
        cache["series"][key] = {"id": sid, "rows": rows}
        print("fetched %s: %d rows" % (sid, len(rows)))
    cache["generated"] = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ")
    json.dump(cache, open(CACHE, "w"))
    return cache

def load_cache():
    if "--fetch" in sys.argv or not os.path.exists(CACHE):
        try:
            return fetch()
        except Exception as e:
            print("fetch failed (%s); falling back to committed cache" % e)
    return json.load(open(CACHE))

def weekly(rows, since=SINCE):
    """Collapse to ISO weeks, last observation in the week wins."""
    out = {}
    for d, v in rows:
        if d < since:
            continue
        dt = datetime.date.fromisoformat(d)
        y, w, _ = dt.isocalendar()
        out[(y, w)] = (d, v)
    return [(k, out[k][0], out[k][1]) for k in sorted(out)]

def main():
    cache = load_cache()
    s = cache["series"]
    wk = {k: weekly(v["rows"]) for k, v in s.items()}

    # baseline: the value closest to BASE_WEEK, per series
    base = {}
    for k, rows in wk.items():
        cand = [r for r in rows if r[1] <= BASE_WEEK]
        base[k] = (cand[-1] if cand else rows[0])

    # one shared week axis: use the gasoline weeks (weekly, dense) and carry
    # the nearest prior value for each other series
    axis = [r for r in wk["gas"]]
    def at(key, date):
        best = None
        for _, d, v in wk[key]:
            if d <= date:
                best = (d, v)
        return best

    series = []
    for (y, w), d, gv in axis:
        b = at("brent", d); dz = at("diesel", d)
        if not b or not dz:
            continue
        idx = 100 * (WEIGHTS["brent"] * b[1] / base["brent"][2]
                     + WEIGHTS["gas"] * gv / base["gas"][2]
                     + WEIGHTS["diesel"] * dz[1] / base["diesel"][2])
        series.append({
            "week": "%d-W%02d" % (y, w),
            "date": d,
            "brent": b[1], "brent_date": b[0],
            "gas": gv, "diesel": dz[1],
            "index": round(idx, 1),
        })

    latest = series[-1]
    def chg(n):
        if len(series) <= n:
            return None
        return round(latest["index"] - series[-1 - n]["index"], 1)

    peak = max(series, key=lambda r: r["index"])
    out = {
        "leg": "M",
        "label": "cost of the base",
        "generated": datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%MZ"),
        "source": {
            "cache_fetched": cache.get("generated"),
            "series": {k: {"id": v["id"], "rows": len(v["rows"]), "last": v["rows"][-1]} for k, v in s.items()},
            "provider": "FRED, Federal Reserve Bank of St. Louis (public domain)",
        },
        "index": {
            "baseline_week": BASE_WEEK,
            "baseline_values": {k: {"date": base[k][1], "value": base[k][2]} for k in base},
            "weights": WEIGHTS,
            "formula": "100 x (0.5 x Brent/Brent_base + 0.3 x gasoline/gasoline_base + 0.2 x diesel/diesel_base)",
        },
        "latest": latest,
        "deltas": {"week": chg(1), "four_week": chg(4), "twelve_week": chg(12)},
        "peak": peak,
        "series": series,
        "caveat": ("These are pump and barrel prices, not household budgets. No income, "
                   "rent or wage series is in this file, so the card reads the price of "
                   "the base, not what a family can afford. The weights are the desk's, "
                   "printed so they can be argued with."),
    }
    json.dump(out, open(OUT, "w"), indent=1)
    print("m_flow: %d weeks, latest %s idx %s (brent %.2f gas %.3f diesel %.3f)" % (
        len(series), latest["date"], latest["index"], latest["brent"], latest["gas"], latest["diesel"]))

if __name__ == "__main__":
    main()
