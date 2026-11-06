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

# ET, not UTC: the box runs UTC so date.today() rolled to tomorrow at 20:00 ET
# and every 'in Nd' label in the calendar was a day short after that (2026-11-05).
TODAY = (datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-4)))).date()
HERE = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.join(HERE, "Internal Telemetry.html")
SPACE = "/space/prediction"

CATS = [
 ("war", "⚔️ War & Conflict", ("war","iran","israel","gaza","russia","ukraine","putin","invasion","strike",
                        "military","hormuz","oil","diesel","sanction")),
 ("gov", "🏛️ Power & Government", ("midterm","election","certification","catalyst","legitimacy","impeach",
                             "shutdown","fascism","authoritar","repression","ice","surveillance","coup",
                             "court","scotus")),
 ("econ", "💵 Economy", ("econ","market","bond","dollar","de-dollar","inflation","price","recession","debt",
                 "tariff","fed","credit","jobs")),
 ("ai", "🤖 AI & Technology", ("agi","ai ","ai-","model","agent","llm","compute","chip")),
 ("sci", "🔬 Science & Health", ("covid","vaccine","health","disease","outbreak","climate","energy")),
 ("other", "🗂️ Everything Else", ()),
]
CAT_SLUGS = {slug: (name, kws) for slug, name, kws in CATS}
OTHER = "🗂️ Everything Else"

def cat_for(t):
    tl = t.lower()
    for slug, name, kws in CATS:
        if kws and any(k in tl for k in kws):
            return name
    return OTHER

def band(c):
    # 2026-11-02: "warm"/"cool"/"cold" are not defined in style.css, so every
    # non-hot pill rendered colourless. Map onto the classes the sheet has.
    if c >= 75: return ("Very likely", "hot")     # .hot   red
    if c >= 55: return ("Likely", "z41")          # .z41   amber
    if c >= 35: return ("Uncertain", "z33")       # .z33   blue
    return ("Unlikely", "z39")                    # .z39   teal


# Filter vocabulary for the state pills (2026-11-02). One state per card, derived
# from the card body — never hardcoded, because "holding" stopped being a legal
# resolution value when the tracking rule landed and a baked count would have kept
# advertising three cards that no longer exist.
STATES = [
    ("hit",     "\u2713 {n} hit",        "hot",  "hits"),
    ("miss",    "\u2717 {n} missed",     "z39",  "misses"),
    ("holding", "{n} holding",           "z41",  "cards held open past their window"),
    ("track",   "{n} on track",          "z33",  "cards still tracking"),
    ("overdue", "{n} past window",       "z41",  "cards past their window with no resolution"),
]


def state_of(o):
    """hit / miss / holding / track / overdue / open — the pill a reader would click."""
    res = (o.get("resolution") or "unresolved")
    if res in ("hit", "miss", "holding"):
        return res
    if (o.get("tracking_state") or "").strip():
        return "track"
    wc = d(o.get("window_closes"))
    if wc and wc < TODAY:
        return "overdue"
    return "open"

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

def cat_slug(name):
    for slug, (cat, _kw) in CAT_SLUGS.items():
        if cat == name:
            return slug
    return "other"


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
            # 2026-11-02: this printed the RESOLUTION date as "closed", so an
            # in-window confirm read as a close date and looked like a late score.
            bits.append(f"resolved {closed.isoformat()}")
        if wc and (not closed or wc != closed):
            bits.append(f"window closed {wc.isoformat()}")
        L = lead_of(o)
        if L["bad"]:
            bits.append("DATES INCOHERENT \u2014 resolved before it was written")
        elif L["lead"] is not None:
            bits.append(f"lead {L['lead']}d from forecast to confirmation")
            if L["margin"] is not None:
                bits.append(f"{L['margin']}d before window close" if L["margin"] >= 0
                            else f"{-L['margin']}d after window close")
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

# --- Confirmation indicator + lead delta (2026-11-04) ----------------------
# Owner requirement: a resolved card must SAY it is resolved, and the register
# must measure how much foreknowledge it actually carried. Two numbers, and they
# are not the same thing:
#   LEAD   = resolution_date - date_made      (how long the call stood before it was tested)
#   MARGIN = window_closes - resolution_date  (how much of its own window the call left unused)
# A card with LEAD 0 was registered the day it resolved: not a forecast, a report.
# That is a finding about the instrument, so the register names it rather than
# burying it inside an average.
def lead_of(o):
    made, res, wc = d(o.get("date_made")), d(o.get("resolution_date")), d(o.get("window_closes"))
    out = {"lead": None, "margin": None, "sameday": False, "late": False, "bad": False}
    if made and res:
        if res < made:
            out["bad"] = True          # resolves before it was written: impossible, data error
        else:
            out["lead"] = (res - made).days
            out["sameday"] = out["lead"] == 0
    if wc and res:
        out["margin"] = (wc - res).days
        out["late"] = out["margin"] < 0
    return out


def conf_badge(o):
    """The indicator. Absent for unresolved cards, so it never competes with a live claim."""
    res = (o.get("resolution") or "unresolved")
    if res not in ("hit", "miss", "holding"):
        return ""
    L = lead_of(o)
    if res == "holding":
        return '<span class="zconf hold">\u25cf HELD OPEN</span>'
    word, cls, glyph = ("CONFIRMED", "hit", "\u2713") if res == "hit" else ("MISSED", "miss", "\u2717")
    bits = [f"{glyph} {word}"]
    if L["lead"] is not None:
        bits.append(f'<span class="zconflead">{L["lead"]}d lead</span>')
    if L["sameday"]:
        cls += " sameday"
        bits.append('<span class="zconflead">same-day, not a forecast</span>')
    elif L["late"]:
        bits.append(f'<span class="zconflead">{-L["margin"]}d past window</span>')
    return f'<span class="zconf {cls}">{" \u00b7 ".join(bits)}</span>'


def card_html(o, catname):
    t = html.escape(o.get("title") or o["basename"].replace("-", " ").title())
    c = conf_of(o)
    if c is not None:
        lab, cls = band(c)
        pill = f'<span class="z35 {cls}">{lab} · {c:.0f}%</span>'
        bar = f'<div class=bar><span style="width:{c:.0f}%"></span></div>'
    else:
        pill = '<span class="z35 z33">unscored</span>'
        bar = ""
    st = (o.get("statement") or "").strip()
    meta = f'<div class=mut style="font-size:.76em;opacity:.85;line-height:1.5;margin-top:4px">{age_line(o)}</div>'
    body = [f'<div class=z7><div class=mut>{html.escape(st)}</div>']
    if o.get("resolution") in ("hit", "miss", "holding") and o.get("resolution_note"):
        body.append(f'<div class=mut style="font-size:.8em;margin-top:6px"><b>Resolution note:</b> {html.escape(str(o["resolution_note"])[:600])}</div>')
    body.append('</div>')
    # Attributes the state filter reads (2026-11-02). data-card = /space basename, the
    # drift guard's exact key (fuzzy title matching mis-paired two Korea cards and
    # reported phantom stale percentages). state / window / confidence / registered
    # are carried here so the filter and its sorts need no second data fetch.
    wc = d(o.get("window_closes"))
    reg = d(o.get("date_made"))
    attrs = (f'data-card="{o["basename"]}" data-cat="{cat_slug(catname)}" '
             f'data-catname="{html.escape(catname)}" data-state="{state_of(o)}" '
             f'data-wc="{(wc or datetime.date(2099, 1, 1)).isoformat()}" '
             f'data-open="{(reg or datetime.date(2099, 1, 1)).isoformat()}" '
             f'data-conf="{(c if c is not None else -1):.0f}"')
    return (f'<div class="z37 zcardwrap"><details class=evt {attrs}><summary><div class=row><span>{t}</span>{conf_badge(o)}{pill}</div>'
            f'{bar}{meta}</summary>{"".join(body)}</details></div>')


def state_pills(name, items):
    """Clickable counts in the group header: one pill per state that actually exists."""
    out = []
    for state, label, cls, phrase in STATES:
        n = sum(1 for o in items if state_of(o) == state)
        if not n:
            continue
        out.append(f'<button type=button class="zpill z35 {cls}" data-fcat="{cat_slug(name)}" data-fstate="{state}" '
                   f'aria-pressed=false title="Pull together the {phrase} in {html.escape(name)}">'
                   f'{label.format(n=n)}</button>')
    return "".join(out)


def global_bar(cards):
    """Board-wide state counts above the register: the same sort, across every category."""
    out = ['<span class="zsbt">Sort by state:</span>']
    out.append(f'<button type=button class="zpill z35" data-fcat="all" data-fstate="any" aria-pressed=false '
               f'title="Show every forecast on the board">all {len(cards)} forecasts</button>')
    for state, label, cls, phrase in STATES:
        n = sum(1 for o in cards if state_of(o) == state)
        if not n:
            continue
        out.append(f'<button type=button class="zpill z35 {cls}" data-fcat="all" data-fstate="{state}" aria-pressed=false '
                   f'title="Pull together every forecast card here: the {phrase}">{label.format(n=n)}</button>')
    out.append('<span class="zsbnote">one click pulls those cards together, oldest window first</span>')
    return "".join(out)

def lead_ledger(cards):
    """The instrument's own report card: how much foreknowledge the resolved calls carried.
    Printed above the register so a good hit rate can never be read without its lead times."""
    closed = [o for o in cards if (o.get("resolution") or "unresolved") in ("hit", "miss")]
    if not closed:
        return ""
    L = [(o, lead_of(o)) for o in closed]
    hits = [1 for o, _ in L if o.get("resolution") == "hit"]
    leads = sorted(x["lead"] for _, x in L if x["lead"] is not None and not x["sameday"])
    sameday = [o for o, x in L if x["sameday"]]
    bad = [o for o, x in L if x["bad"]]
    early = [1 for _, x in L if x["margin"] is not None and x["margin"] > 0]
    late = sum(1 for _, x in L if x["late"])
    med = (leads[len(leads)//2] if len(leads) % 2 else
           int((leads[len(leads)//2 - 1] + leads[len(leads)//2]) / 2 + 0.5)) if leads else None
    cells = [
        (f"{len(hits)}/{len(closed)}", "scored hit rate", "of the cards that have resolved"),
        (f"{med}d" if med is not None else "\u2014", "median lead", "forecast to confirmation, same-day calls excluded"),
        (f"{len(early)}/{len(closed)}", "confirmed inside window", "resolved before the window they were given"),
        (f"{len(sameday)}", "same-day calls", "registered the day they resolved: a report, not a forecast"),
    ]
    out = ['<div class="zledger">',
           '<div class="zledhead"><b>Confirmation ledger</b> \u2014 every resolved card carries a confirmation badge and a lead delta. '
           'Lead is the distance from forecast to confirmation: the foreknowledge the call actually bought.</div>',
           '<div class="zledgrid">']
    for v, lab, sub in cells:
        out.append(f'<div class="zledcell"><div class="zledv">{v}</div>'
                   f'<div class="zledl">{lab}</div><div class="zleds">{sub}</div></div>')
    out.append('</div>')
    if late:
        out.append(f'<div class="zlednote">{late} card{"s" if late != 1 else ""} resolved after its own window closed \u2014 '
                   'shown as past-window on the card, never folded into the lead average.</div>')
    if bad:
        names = ", ".join(html.escape(o["basename"]) for o in bad)
        out.append(f'<div class="zledbad"><b>Dates incoherent:</b> resolved before written \u2014 {names}</div>')
    out.append('</div>')
    return "".join(out)


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

    # --- state bar + filter view (2026-11-02): the counts in group headers are
    # clickable, and clicking one moves those cards into #zregview — a flat stack
    # sorted by window close, so "which of these actually resolved" is one click
    # instead of scrolling 69 accordions looking for the coloured pills.
    R.append(lead_ledger(cards))
    R.append(f'<div id="zregbar" class="zsbar">{global_bar(cards)}</div>')
    R.append('<div id="zregview" class="zsview" hidden></div>')
    R.append('<div id="zreg">')

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
            # overdue rows read red, closing-this-week amber, the rest muted
            _cls = "hot" if n < 0 else ("z41" if n <= 7 else "z33")
            rows.append(f'<div class=row><span>{t}</span><span class="z35 {_cls}">{wc.isoformat()} · {label}</span></div>')
        R.append('<details><summary><b>⏳ Resolving next 45 days</b> <span class=mut>'
                 f'{len(soon)} forecasts due</span> <span class="z35 z41">oldest first by window</span></summary>'
                 '<div class="z37" style="padding:6px 2px">' + "".join(rows) +
                 '<div class=mut style="font-size:.8em;margin-top:8px">A window is a promise to answer. Cards that '
                 'reach their close date are graded HIT or MISS — never quietly extended. A card still being '
                 'tracked past its window says so on the card; it does not get a new date.</div></div></details>')

    # --- theme groups
    reg = {}
    for o in cards:
        reg.setdefault(cat_for(o.get("title") or o["basename"]), []).append(o)
    order = [n for _s, n, _k in CATS]
    for name in order:
        items = reg.get(name)
        if not items: continue
        # open first, soonest close first; resolved cards sink to the bottom
        def key(o):
            res = o.get("resolution") or "unresolved"
            wc = d(o.get("window_closes")) or datetime.date(2099, 1, 1)
            return (1 if res in ("hit", "miss") else 0, wc, -(conf_of(o) or 0))
        items = sorted(items, key=key)
        badges = state_pills(name, items)
        R.append(f'<details class=zcat data-cat="{cat_slug(name)}"><summary><b>{name}</b> '
                 f'<span class=mut>{len(items)} forecasts</span> {badges}</summary>'
                 f'<div class="z37 zgrp">{"".join(card_html(o, name) for o in items)}</div></details>')
    R.append('</div>')
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
