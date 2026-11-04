# Changelog

## 2026-11-04

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
