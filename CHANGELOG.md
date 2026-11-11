# Changelog

### Reference sections folded, change log tabulated (v4.29-preview)
- **Sections 4, 5 and 7 folded closed** (institutional coverage, registers, data dictionary). Full headings stay on the closed lines; a lead note above section 4 says they are reference material.
- **Section 8 rebuilt as a table**: date / version / what changed, newest first, 22 entries. The two newest entries had been loose outside the panel with the rest inside it, so ordering was broken at the top.
- **Breaks added inside entries**: numbered sub-points and bold lead-ins break onto their own lines.
- No reading changed.

### Section 3's working papers folded away (v4.28-preview)
- **3.5 corpus composition, 3.6 instrument register, 3.7 base rate, 3.8 S&H panel, 3.9 blind draw and 3.10 replication now sit in collapsible folds**, closed by default. Each fold keeps its numbered heading and date as the summary line, with an OPEN/CLOSE cue.
- **Nothing removed.** The lay reader meets 3.1–3.4 (rate, direction, function, what would falsify it); the reader who wants to challenge the model opens the folds.
- **The how-to-read note now says so**: everything below 3.4 is the instrument's working papers, folded, nothing hidden and nothing needs opening to read the board.
- No reading changed.

## 2026-11-11

### Section 3 says how to read it (v4.27-preview)
- **Heading subtitle removed.** "3 · Absorption velocity — the other thing the instrument could not see" is now "3 · Absorption velocity". The subtitle described the section's history to the analyst, not its contents to a reader.
- **Plain-language note added at the top of the panel**: specimens per week is the number that does the work (33 this week, 8 the week before); it is not a score, is not comparable to section 2, and measures how fast the audience that would have to accept force is being prepared rather than how cruel the feed is. Both limits stated in the note — the desk decides what counts as a specimen, and the series only begins at W38.
- No reading changed.

## 2026-11-11

### Flow gauges for M, G and E — and T named as the leg without one (v4.26-preview)
- **M gets a series for the first time.** `build_m_flow.py` indexes Brent (DCOILBRENTEU), retail gasoline (GASREGW) and diesel (GASDESW) to the week of 2026-06-01 = 100, weighted 0.5/0.3/0.2, from a committed FRED cache (`m_flow_cache.json`). Runs inside `sync_data.sh`. Current: 108.4, down from a 126.5 peak (week of 2026-10-05).
- **Three matching gauge cards** open 2.4: big number, one bar per observation with hover/tab read-out, three key figures, and a "how to read it" note in plain terms.
- **T is stated as the leg that cannot carry a gauge**, with the reason, rather than silently omitted.
- **Section restructured**: 2.4a is the M weekly table, 2.4b holds the E and G detail panels. The lead now says the three readings are the same as the 2.1 row at working resolution.
- **Denominator note added** across all three: the desk controls every denominator, so a rate can move because the world moved or because the recording did.
- **Collapsed-denominator caveat on the cards themselves**: where the latest month was written in under 60% of the previous month's volume (Nov: 20 entries vs 189), the G and E cards say so in their own note rather than printing an inflated per-hundred figure.

## 2026-11-11

### Gap row removed from 2.2 (v4.25-preview)
- **The gap marker is gone from all four legs.** It compared the anchor-computed load against the original hand-set number — a migration artefact, not a reading. The hand-set numbers predate the current model and have no standing against it, so the difference reads as a finding to anyone who wasn't here for the cutover.
- **Two notes removed with it**: the ±5 quantisation note (M, E) and the vacuous-identity note (G). Both existed only to explain the gap.
- **Live board reads kept**, and the panel note now says it retires at cutover and that the computed load is the reading the model runs on.
- **T's note keeps its substance** — 82 had no anchors behind it, 40 is what four anchored questions produce — with the −42 subtraction removed.
- No reading changed.

## 2026-11-10

### 2.3 gauges removed, table promoted (v4.24-preview)
- **The twelve gauges are gone.** They restated the table below them at three times the height, and each needle could only be read against its own arc — twelve separate scales where the panel's whole job is ranking. The table already shared a left edge.
- **Table sorted worst-first.** Civil Service at 91 was sixth row down; the reader's first question is what is worst.
- **Tick at 80 on every bar**, so Critical is a mark on the scale rather than a word in the last column.
- **Δ moved to the bar's end** as a small numeral (green better, amber worse, violet "new"), replacing its own column.
- **Set-v2 comparability stated in the note**: the mean and Critical share break at the 8→12 dial change; the individual scores do not.

### Institutional withdrawals renamed, plus a reading guide for the whole macro row (v4.23-preview)
- **"Legitimation flow" renamed "Institutional withdrawals"** at both 2.1 and 2.4-g. The model register word is why it was opaque: nobody arrives knowing that "legitimation flow" counts refusals.
- **The card now says how to read it**: what is being counted, why the big number is a rate and not the running total, why the ratio 13:1 matters more than either count, why the 25-per-100 must be ignored this month (20 entries written against 189), and that two months is a level with no baseline.
- **New section intro at 2.1** answering what the four macro numbers mean together: four different questions, four different scales and clocks, higher-is-worse as the only shared property, and the row's single purpose — pressure against the capacity to resist.

### Institutional stock renamed to Institutional Pressure, with a reading guide (v4.22-preview)
- **Card renamed "Institutional Pressure."** STOCK stays as the register tag — that is the model's language, and the label is the reader's.
- **The note now says how to read it** rather than how the number is derived: what the 0–100 scale asks (how far a body has been captured), why an average across 12 bodies hides the composition (8 at Critical, 4 at Warning, nothing below), why the worst dial — Civil Service at 91 — is the reading to watch, and what the card cannot show (speed of movement, which only appears in per-dial deltas at 2.3).
- All counts derive at render time from the dial set, including the Critical share.

### The board opens by saying what it is measuring (v4.21-preview)
- **The enforcement-flow note now explains how to read the card.** Four beats: what the bars count, why they fall (the denominator is the writing, which rose tenfold), what the window can actually support (only the two months where attention held level), and what would settle it. The last line names the instrument's weakness — the desk's own attention is the ruler.
- Month labels are spelled out ("May 2026", not "05/26"); the beats are separated as paragraphs rather than run together.
- Every figure in the note is read off the series at render time.
- **Enforcement flow is now readable without the method section.** A six-bar sparkline sits under the number, one bar per month, scaled to the controlled rate. Hover, tab or tap a bar and the line beneath reads that month back in plain terms — "2026-07 — 7 enforcement events against 18 entries written that month, or 38.9 per hundred entries." The peak month is marked; the rest are neutral. Clicking a bar jumps to that month's row at 2.4, which flashes.
- **The note leads with what the movement means** before it quotes the statistics. Raw count and rate fall in opposite directions across the window, which looks like a contradiction until the denominator is stated; the note now says it in two sentences.
- Everything above is derived at render time from `data.flow_panel`, which the export regenerates. No new hand-set numbers.
- **Legs fired now lists its legs.** Under the phase line, one row per leg — letter, name, FIRED or ABSENT — so "3 of 4" can be read without scrolling to 2.2. No load figures in the rows on purpose: a leg can carry 82 and read ABSENT, and printing the score beside the state invites exactly that conflation.
- **Each row defines its leg on hover**, tap and focus: the plain-language line from `data.json mget.legs[].plain` first, then the canonical `/space/term` definition, so the tooltip is generated in both halves and the term gate still resolves it.
- **Removed the build commentary at the top of Model updates** — "This is the proposed layout running on real data…" That paragraph described the state of the build to the operator, not to a reader. The section now opens on what was learned from the old model.
- Panel formerly titled **"About this page"** renamed **"Model updates"** (16:30 ET). The panel's content is no longer a note about the page's layout; it is the record of what the model changed and why, sitting directly under the theory it belongs to. The old title described the container, the new one describes the contents.
- New opening section before "About this page": **MGET stated in four plain-language paragraphs** — the enclosing force and the resistance it provokes, the mutation lineage (slavery → feudalism → capitalism → algorithmic enclosure), the crisis point Strauss and Howe call a turning, and the three-way unification: S&H supply the period and phase language, Turchin the measurable drivers, Polanyi the shape of the reaction. Nobody had joined them; that is the claim.
- The section closes on the standard the instrument is held to: **the theory must be wrong in public**, with three stated falsifiers — a turning indistinguishable from ordinary institutional wear, a resistance that fails to appear where enclosure is deepest, and a crisis arriving with no prior loss of legitimacy.
- Editorial corrections carried in from drafting: "citizens" → "people" (slavery enclosed property, not citizens), "measurable" restored to the definition of enclosure (measurement precedes commodification and is what links the four mutations), and "applies S&H to Turchin and Polanyi" rewritten as an assembly of three components rather than one applied to two.
- No numbers changed. Daily Read remains section 1; this is framing above it.

## 2026-11-06

### Belief ledger becomes section 0 — first major change since v1 (v4.14-preview)
- The board now opens on **what it used to claim**. Seven v1 statements, the test that moved each, and the verdict: calendar **downgraded** (failed its first out-of-sample test), continental windows **withdrawn** (RR 2.44→5.74 on start-year choice alone), window independence **refuted** (tautological inside English history), corpus-as-population **revised**, legs 1–2 and leg 4 **rebuilt**, velocity **split**.
- Backing objects: `/space/belief_ledger` — one object per row, verdicts never deleted, changed only by a later dated test. Rule: `/space/protocol/belief-ledger.json`.
- Five open commitments carry a falsifier and a scoring date. An experiment run in public without a stop condition becomes permanent framing.
- **Snapshotting begins.** Any build making a structural model change is frozen before it ships — leg added/removed/redefined, instrument rebuilt, deck or calendar thesis altered, or a change to what the board claims. Routine data refreshes and new readings on unchanged instruments are not snapshotted (rule narrowed 19:03: archiving every reading change implied every number shift was a model revision). listed in the internal archive (not published). Two snapshots: `2026-11-06-1755-v4.13-preview.html`, `2026-11-06-1802-v4.14-preview.html`. Snapshots are immutable, stay on the machine, and are excluded from this repo; corrections go in the next one.
- No numbers were recomputed in this build. This is a record-keeping release, and it is the one that makes the rest checkable.


### Four legs instrumented — two on external baselines, one on a stored register (v4.9-preview)
- Legs 1 and 2 were **specified but empty**: leg 1 needed `repression_event.processing_status/.resolution_date/.processor`, which no record has; leg 2 needed seatings, which do not exist in `/space` at all, so its denominator was structurally zero. Both now read **external series that already cover the period**, and neither depends on this desk noticing anything.
- **Leg 1 baseline, 26 years** — nationwide injunctions. Harvard Law Review counts 6 (2001–08) and 12 (2009–16) under a narrower definition; CRS R48467 gives 86 (2017–20) and 28 (2021–24); CRS R48476 gives 25 in the first 100 days of 2025, ~91 annualised. **The definition breaks at 2017**, so the pre-2017 years are shown as a band (≤1.5/yr) and never joined to the later points. The 2025 figure is labelled an **estimate**, not a realised count.
- **Leg 2 baseline, 45 years** — Tenpas/Brookings senior-staff turnover: 9% (Obama y1), 17% (Reagan y1, previous record), 34% (Trump I y1), ~56% cumulative (Trump II at ~20 months, **not yet comparable to a year-one figure**). The rate is published; the claim resting on it is not — displacement needs an exit-type split (forced / pressured / promoted / voluntary) that has not been coded.
- **Leg 4 register stored.** The 14 scored docking cases existed only as prose in a note body, so the board printed "14 scored candidate acts" and no code could count them. One object per case in `/space/docking_case` (14 fields → `d_fired`, `direction`, `order_survived`): **7 of 14 fired, 0 of 7 false alarms, direction 6 replacement / 1 restoration.**
- Leg 3 unchanged: 56% fence share on 6 of 9 assigned firms, one observation, no series.
- Register line now reads **1 of 4 fired, 4 of 4 instrumented, 2 of 4 thin** — replacing "1 of 4 legs measured", which is no longer true.
- No gate-bearing generated file changed; `data.json` untouched and this build was not pushed.


## 2026-11-04

### Direction fix + `prose.panel-direction` gate rule (v3.11.5)
- Two places said the **Institutional Stress dials were "above"** — the Governance explainer and the panel footer. Model State renders first, so the dials sit **below**. Both now read "below"; `mget_state.json` derivation wording aligned.
- New gate rule `prose.panel-direction`: every direction word about a named panel is read against actual document order and **fails the run on a mismatch**. Fault-injected (reintroducing "above" fails at byte 9171; restoring passes).
- No numbers changed — a reading error, not a measurement error.

### Leg 4 docking test — a gauge with no moment cannot fire (v3.11.4)
- Leg 4 carried nine words for "not fired" (ABSENT, HOLD, STABLE, EROSION, ANTI-ALIGNED, PENDING, SPLIT) and **no definition of the moment it would fire on**, so it was adjudicated by adjective rather than by act. That is why 82 load could sit beside absence with no stated boundary.
- State now fires on the first dated act satisfying **D1–D4** (`/space/protocol/leg4-docking-test.json`): a refusal that sticks for 30 days; organised vanguard endorsement of a replacement authority; a veto institution removing executive capacity rather than delaying it; a transfer act that completes. **Persistence:** holds only if a second dock lands within 90 days; a single dock is a tremor and reverts.
- Supersedes the earlier count test (3+ months, 5+ named defections), which had duration but no moment.
- Re-coded against 25 corpus cases: nine adjectives → three states, **6 verdicts that used a non-absent word fell to ABSENT** for want of a dated act, **0 of 7** null years and designed false-positive traps fired (MacArthur 1951, court-packing 1937, impeachment 1998-99, 2017, 1993, 2022, 2018).
- Boundary case recorded in the definition: **1890–1914** scored leg 4 absent and the order ruptured anyway — by external capture, not vanguard replacement.
- No card field added, so no dictionary entry required; `mget_state.json` T `definition`, `why` and the threshold `basis` rewritten.

### Confirmation badge and lead delta (v3.11.3)
- Resolved cards carry a badge in the headline row: `✓ CONFIRMED`, `✗ MISSED`, `● HELD OPEN`; dashed amber = same-day registration.
- Each resolved card prints its **lead delta** (forecast date → confirmation date) and window margin.
- **Confirmation ledger** strip: 6/12 scored hit rate, 51d median lead (same-day excluded), 6/12 confirmed inside window, 4 same-day calls, 2 past-window resolutions.
- New gate rules `confirmation.badge`, `confirmation.lead`, `confirmation.dates` — all fault-injected (badges stripped → 3 FAILs; resolution_date backdated before date_made → `resolved before written`).

### Literal escape guard (v3.11.2)
- 18 literal `\uXXXX` escapes were rendering as text in the Model State panel ("100 \u00d7 the mean"). Decoded in prose; same class of leak cleaned from five `/space` records.
- New gate rule `prose.no-literal-escapes` checks **rendered** prose only, so escapes inside script source (regex classes, ▲▼ glyphs) are untouched. Fault-injected: 1 injected escape → FAIL, then removed.

### Register-drift warning fixed (v3.11.1)
- The drift check parsed baked per-card percentages from the page, but the register renders live from `data.json` — so 83 scored cards read as "off-register" on every run with nothing wrong. Now compares against `data.json.predictions` and names its source in the output.
- Upload protocol written into `README.md`: footer version, change log (page + CHANGELOG.md), Data Dictionary, version consistency across all four places, gate order after every pull.

### Model State definitions (v3.11.0)
- State and load separated on the panel. Each gauge prints the leg's operational state (FIRED / ABSENT / CONTESTED) beside its load, so a load of 82 with leg 4 absent reads as "conditions heavy, threshold not crossed" rather than "nearly fired."
- LOAD defined on the panel and in the Data Dictionary: 100 × mean of four named anchors, each 0–5 on a fixed six-point scale; an anchor without a cited observable cannot score above 2; equal weights stated as a design choice. Bands are display-only and can never produce a state.
- Cards explicitly do not feed load. Card-mass weighting was computed and rejected (it would rank Governance first, Enclosure last — attention priced as evidence).
- Data Dictionary gained: Model State, the four legs with their canon attributions (Tainter / Turchin / Polanyi / vanguard alignment), Load, State, Gate, Lane prices, Register load.
- `node verify_prod.js` gate extended: `docs.changelog` asserts the footer version appears in a change-log entry, `docs.dictionary` asserts every published card field has an entry.
- Staging-only runs are now first-class: `STAGING_ONLY=1 ./sync_data.sh` skips the prod push and is exempted from `deploy.match` (which otherwise compares against the prod URL and fails by construction). Approval is still a human step, not a flag default.

### Model State — MGET (v3.10.0)
- New panel above Institutional Stress: four leg dials (Material, Governance, Enclosure, Turning), each with a plain-language explainer box and a stated derivation, plus the 3-of-4 gate row and the 90-day lane prices.
- All 88 forecast cards now carry a `leg_primary` classifier in /space (`M`/`G`/`E`/`T`/`N`). Register load is derived at sync from those fields, never hand-typed.
- Governance dial derives from the mean of the eight institutional dials so the two panels cannot disagree.
- `mget_state.json` is the hand-edited source of truth, imported into `data.json.mget` each run — same arrangement as `institutions.json`. Sync never rewrites a dial, and warns if the lane partition stops summing to 100.

## 2026-10-14

### Infrastructure: GitHub Pages → Cloudflare Pages migration (15:00–15:15 ET)
- Migrated hosting to Cloudflare Pages (Git integration, no build step; publishes `main` on every push). Custom domain `dash.cass-intelligence.com` activated on Cloudflare; GitHub Pages unpublished and custom domain detached on GitHub. `CNAME` removed from repo.
- Root cause of migration: GitHub Pages deployment-lock corruption — repeated 400 "in progress" errors on the `github-pages` environment (runs #759–#765), unrecoverable via requeue, rerun, empty commits, or deleting the zombie run.

### Dashboard fixes
- **v3.7.0** (12:32 ET): added Institutional Stress gauges — SVG dials rendered live from `institutions.json` (fallback: baked overlay).
- 14:40 ET: unified needle/arc trig convention (needles were pegged at wrong end of arc; now 0 = left, 100 = right).
- **v3.7.1** (15:19 ET): bands now derived from score in the renderer (single source of truth) — label, color, and needle can no longer disagree. Election Offices (73) and Congress (72) recalibrated Critical → **Warning** per the reference guide (60–74 = Warning).
- 15:31 ET: fixed missing-paren syntax error from the band-derivation edit (panel rendered empty).
- 15:33 ET: needle + hub changed to black so the needle stays visible over the Critical band.
- 12:27 ET: `archive.html` added to the sync add-list (was 404 on live).
- 12:09 ET: added searchable Daily Read archive (`archive.html`) with auto-archive step in the daily sync (owner-approved).

### Protocol
- Push protocol amended after the lock incidents: batch commits into a single push; never cancel/requeue mid-flight (cancellation mid-deploy is what creates the phantom lock); syntax-check all script blocks before push.
