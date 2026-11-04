# Changelog

## 2026-11-04

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
