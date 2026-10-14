# Changelog

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
