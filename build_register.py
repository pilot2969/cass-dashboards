#!/usr/bin/env python3
"""Regenerate the public forecast register inside Internal Telemetry.html.

Why this file exists: the register is baked HTML, not rendered from data.json, so
a card that changes in /space does not move on the page until this runs. Two
incidents (2026-11-02) came from editing /space and assuming the page followed.

Added 2026-11-02 with the v1 forecast-card schema: every card now prints its
class (EVENT / PERSISTENCE / THESIS / MECHANISM), its registration date and age,
its window close and days-to-close, and its resolution state. Groups are sorted
open-first by soonest close, so stale cards sink and closing cards rise.

Usage: python3 build_register.py [--dry]
"""
import glob, html, json, os, re, sys, datetime

TODAY = datetime.date(2026, 11, 2)
HERE = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.join(HERE, "Internal Telemetry.html")
SPACE = "/space/prediction"

CATS = [
 ("⚔️ War & Conflict", ("war","iran","israel","gaza","russia","ukraine","putin","invasion","strike",
                        "military","hormuz","oil","diesel","sanction")),
 ("🏛️ Power & Government", ("midterm","election","certification","catalyst","legitimacy","impeach",
                             "shutdown","fascism","authoritar","repression","ice","surveillance","coup",
                             "court","scotus")),
 ("💵 Economy", ("econ","market","bond","dollar","de-dollar","inflation","price","recession","debt",
                 "tariff","fed","credit","jobs")),
 ("🤖 AI & Technology", ("agi","ai ","ai-","model","agent","llm","compute","chip")),
 ("🔬 Science & Health", ("covid","vaccine","health","disease","outbreak","climate","energy")),
]

def cat_for(t):
    tl = t.lower()
    for name, kws in CATS:
        if any(k in tl for k in kws):
            return name
    return "🗂️ Everything Else"

def band(c):
    if c >= 75: return ("Very likely", "hot")
    if c >= 55: return ("Likely", "warm")
    if c >= 35: return ("Uncertain", "cool")
    return ("Unlikely", "cold")

def d(s):
    try: return datetime.date.fromisoformat(str(s)[:10])
    except Exception: return None

def days(a, b):  # b - a in days, signed
    return (b - a).days

def load():
    internal = set()
    ip = os.path.join(HERE, "internal_cards.txt")
    if os.path.exists(ip):
        internal = {l.strip() for l in open(ip) if l.strip()}
    out = []
    for f in sorted(glob.glob(SPACE + "/*.json")):
        if f.endswith(".schema.json"):
            continue
        b = os.path.basename(f)[:-5]
        if b in internal:
            continue
        o = json.load(open(f))
        o["basename"] = b
        out.append(o)
    return out

def conf_of(o):
    c = o.get("confidence_score")
    try: return float(c)
    except Exception: return None

def age_line(o):
    """The line that answers 'how old is this?'"""
    bits = []
    reg = d(o.get("date_made"))
    if reg:
        bits.append(f"opened {reg.isoformat()} ({days(reg, TODAY)}d)")
    cls = o.get("card_class") or "—"
    bits.insert(0, cls)
    wc = d(o.get("window_closes"))
    res = o.get("resolution") or "unresolved"
    if res in ("hit", "miss", "holding"):
        closed = d(o.get("resolution_date")) or wc
        tag = {"hit": "CLOSED — HIT", "miss": "CLOSED — MISS", "holding": "HELD OPEN (holding)"}[res]
        bits.append(f'<b>{tag}</b>')
        if closed:
            bits.append(f"closed {closed.isoformat()}")
    elif wc:
        n = days(TODAY, wc)
        when = f"in {n}d" if n > 0 else ("today" if n == 0 else f"{abs(n)}d ago — overdue")
        bits.append(f"window closes {wc.isoformat()} ({when})")
    else:
        bits.append("no window set")
    if o.get("skill_eligible") is False:
        bits.append("scored — not skill-eligible")
    ps = o.get("public_status")
    if ps == "pending_adjudication":
        bits.append("published ahead of the gate")
    elif ps == "internal":
        bits.append("internal")
    return " · ".join(bits)

def card_html(o):
    t = html.escape(o.get("title") or o["basename"].replace("-", " ").title())
    c = conf_of(o)
    if c is not None:
        lab, cls = band(c)
        pill = f'<span class="z35 {cls}">{lab} · {c:.0f}%</span>'
        bar = f'<div class=bar><span style="width:{c:.0f}%"></span></div>'
    else:
        pill = '<span class="z35 cool">unscored</span>'
        bar = ""
    st = (o.get("statement") or "").strip()
    meta = f'<div class=mut style="font-size:.76em;opacity:.85;line-height:1.5;margin-top:4px">{age_line(o)}</div>'
    body = [f'<div class=z7><div class=mut>{html.escape(st)}</div>']
    if o.get("resolution") in ("hit", "miss", "holding") and o.get("resolution_note"):
        body.append(f'<div class=mut style="font-size:.8em;margin-top:6px"><b>Resolution note:</b> {html.escape(str(o["resolution_note"])[:600])}</div>')
    body.append('</div>')
    return (f'<div class="z37"><details class=evt><summary><div class=row><span>{t}</span>{pill}</div>'
            f'{bar}{meta}</summary>{"".join(body)}</details></div>')

def build():
    cards = load()
    tracked = len(cards)
    scored = [o for o in cards if conf_of(o) is not None]
    openc = [o for o in cards if (o.get("resolution") or "unresolved") not in ("hit", "miss")]
    closed = [o for o in cards if (o.get("resolution") or "unresolved") in ("hit", "miss")]

    R = []
    gate_pending = sum(1 for o in cards if o.get("public_status") == "pending_adjudication")
    R.append(f"<h2>What we're tracking ({len(scored)} scored forecasts · {tracked} tracked · "
             f"{len(openc)} open · {len(closed)} resolved"
             + (f" · {gate_pending} ahead of the gate" if gate_pending else "") + ")</h2>")

    # --- resolution calendar: what is about to close. This is the answer to
    # "it's a large stack, I can't tell what's old" — the future edge of the
    # board, sorted by when it has to answer for itself.
    soon = []
    for o in openc:
        wc = d(o.get("window_closes"))
        if not wc: continue
        n = days(TODAY, wc)
        if n <= 45:
            soon.append((wc, n, o))
    soon.sort(key=lambda x: (x[0], -(conf_of(x[2]) or 0)))
    if soon:
        rows = []
        for wc, n, o in soon:
            label = "today" if n == 0 else (f"in {n}d" if n > 0 else f"{abs(n)}d past window — unresolved")
            t = html.escape(o.get("title") or o["basename"])
            c = conf_of(o) or 0
            rows.append(f'<div class=row><span>{t}</span><span class="z35 cool">{wc.isoformat()} · {label}</span></div>')
        R.append('<details><summary><b>⏳ Resolving next 45 days</b> <span class=mut>'
                 f'{len(soon)} forecasts due</span> <span class="z35 warm">oldest first by window</span></summary>'
                 '<div class="z37" style="padding:6px 2px">' + "".join(rows) +
                 '<div class=mut style="font-size:.8em;margin-top:8px">A window is a promise to answer. Cards that '
                 'reach their close date are graded HIT, MISS, or HELD OPEN — never quietly extended.</div></div></details>')

    # --- theme groups
    reg = {}
    for o in cards:
        reg.setdefault(cat_for(o.get("title") or o["basename"]), []).append(o)
    order = [n for n, _ in CATS] + ["🗂️ Everything Else"]
    for name in order:
        items = reg.get(name)
        if not items: continue
        # open first, soonest close first; resolved cards sink to the bottom
        def key(o):
            res = o.get("resolution") or "unresolved"
            wc = d(o.get("window_closes")) or datetime.date(2099, 1, 1)
            return (1 if res in ("hit", "miss") else 0, wc, -(conf_of(o) or 0))
        items = sorted(items, key=key)
        n_hit = sum(1 for o in items if o.get("resolution") == "hit")
        n_miss = sum(1 for o in items if o.get("resolution") == "miss")
        n_hold = sum(1 for o in items if o.get("resolution") == "holding")
        badges = ""
        if n_hit: badges += f'<span class="z35 hot">✓ {n_hit} hit</span>'
        if n_miss: badges += f'<span class="z35 cold">✗ {n_miss} missed</span>'
        if n_hold: badges += f'<span class="z35 z41">{n_hold} holding</span>'
        R.append(f'<details><summary><b>{name}</b> <span class=mut>{len(items)} forecasts</span> {badges}</summary>'
                 f'<div class="z37">{"".join(card_html(o) for o in items)}</div></details>')
    return "".join(R), dict(scored=len(scored), tracked=tracked, open=len(openc), closed=len(closed))

def main():
    src = open(SHELL, encoding="utf-8").read()
    m = re.search(r"<h2>What we[^<]*tracking[^<]*</h2>", src)
    if not m:
        sys.exit("FATAL: register header not found in Internal Telemetry.html")
    start = m.start()
    nxt = src.find("<h2>", m.end())
    if nxt < 0:
        sys.exit("FATAL: no section after the register; refusing to rewrite to end of file")
    new, counts = build()
    out = src[:start] + new + src[nxt:]
    print(f"register rebuilt: {counts}")
    if "--dry" in sys.argv:
        print("dry run, nothing written"); return
    open(SHELL, "w", encoding="utf-8").write(out)
    print(f"written {SHELL} ({len(out)} bytes)")

if __name__ == "__main__":
    main()
