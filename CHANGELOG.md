# CASS Dashboard — Change Log

All notable changes. Newest first. Dates are US Eastern.
This file mirrors (and extends) the Version History table rendered in `index.html`.

## 2026-10-09 · v3.3.0 (public briefing)
- **All-new public briefing page (`Internal Telemetry.html`)**, plain-language register: About-the-board intro, hand-selected Big Questions (owner-curated 2026-10-09), macro forecast on top, full forecast register grouped by plain-language themes.
- **Threshold Watch promoted to a standing warning banner** — red-bordered, always visible, no longer collapsed; issue/expiration dates retained in the header per owner request.
- **Event cards fully expandable** — statements are no longer truncated without recourse; each card opens to its full text.
- Owner-sign-off gate restated: design changes ship to staging only until explicitly greenlit; prod receives data-only pushes under the 2026-10-05 PUSH-TARGET amendment.
- Deploy hardening: push failure now aborts the deploy (the old `| tail -1` guard masked failed pushes as success).
- Staging root (`index.html`) now redirects to the briefing instead of the internal shell.

## 2026-09-30 · v3.1.1 (pipeline)
- **Sync pipeline bug fixed (found by live failure, twice):** the stranded-commit guard echoed its warning but never pushed — the unconditional second `git commit` exited 1 on "nothing to commit," aborting the script before the push line ran. Guard now pushes when stranded commits exist; second commit is conditional (`git diff --cached --quiet`).
- Failure taxonomy so far: dirty-tree rebase abort (edit in tree), regeneration-identical false clean (gate passes while commit is stranded), guard-as-lie (echo without push). All three closed today.
- Evening edition Daily Read: Quantico State of the Force (six initiatives; AUTOWARCOM, Project Meridian, FORTRESS America, Office of Religious Affairs), 20% billet cut w/ Jan 1 2027 deadline, Iraq withdrawal complete, Nowa Deba package incident.

## 2026-09-27 · v3.1.0
- **New "Today's Read" panel** — collapsible, open-by-default section above the Forecast Register: hand-authored plain-English daily trend summary (10th-grade reading level) with a "Watching next" list. Rendered from `Daily Read.md` at build time; new `daily_read` field in `data.json`; loader added to `deploy-cass.sh`.
- **Wire sweep recalibration** — scoring switched from raw Google News result counts to corpus-share (hits per 100 aggregated-corpus headlines), fixing the ~100-item instrument ceiling that pinned four topic buckets; keyword sets tightened. Wire sweep now runs 9 sources.
- **DW (Deutsche Welle) added** as ninth source via native feed — first non-US-native source; covers the Eurasia-settlement framing lane.
- **Eurasia Hemisphere Pivot card moved 68→70** on the Argentina peg-defense entry (backfilled to /space).
- Version history table updated; `meta.version` → `3.1.0-data-layer`.

## 2026-09-22 · v3.0.2
- Movers card persistence fix (export now preserves movers across deploys; canonical hand-maintained overlay); timestamp rendering fixed; stateful-bug class closed.
- Methodology section updated: headline suite n=7 macro eras, 6-run policy track reported separately, Falsifiability Collapse Protocol promoted to standing clause.

## 2026-09-21 · v3.0.1
- Staging pipeline rebuilt on MCP push protocol (staging-first verify before prod); data rebuilt from canonical /space at 215 ledger entries; VERSION bumped.

## 2026-09-21 · v3.0.0
- Collapsible MGET Ledger (215 entries, newest-first, verdict filter chips); header explainer defining the four legs and verdict vocabulary.
- Fix: prediction card field mismatch (`confidence_score` → `confidence`) restoring badge/sort/share-card fidelity.

## 2026-09-21 · v3.0.0 (data layer)
- Shard-aware loader (renderer expands `_sharded` arrays, killing the `predictions.forEach` error).
- Movers card rebuilt: collapsed by default, descending order, 24h window keyed to newest ledger entry, one-line format.
- `macro_forecast` restored as build-time derivation from canonical prediction card.
- Deploy pipeline hardened: 40KB transport cap, stdin payloads, API-based verification.

## 2026-09-17 · v2.8.1–v2.8.7
- Share-card engine rebuilt after a deploy incident: shell/data separation hardened, card renderer pulls live sections (plain-English, evidence, falsifier) at click time; plain-English auto-draft persisted in the export layer.

## 2026-09-17 · v2.7
- 📸 Share Card on every prediction card and the macro forecast header: claim, plain-English translation, evidence chain, armed falsifier as one shareable image.

## 2026-09-17 · v2.6
- Sparklines removed (low signal-to-noise); share-card engine v1 shipped.

## 2026-09-15 · v2.4
- Data Dictionary section (15 field definitions) and in-shell Change Log added.
- Data layer rebuilt from live source-of-truth export after a stale-data bug was caught: Hormuz entry flipped to confirmed per its own falsifier criteria.
- Confidence-history sparklines added to every prediction card (daily snapshots auto-merged via persistent `history.json`).

## 2026-09-14 · v2.3
- Methodology explainer section: MGET legs, falsifier discipline, lead-time, Threshold Watch, blind backtest results.

## 2026-09-14 · v2.2
- Professional layout; log/resolve dates with lead-time display; Threshold Watch banner indicator with expandable issuance text.

## 2026-09-14 · v2.1
- Forecast language, confidence normalization, public header.

## 2026-09-14 · v2.0
- Data-driven rebuild: board renders live from `data.json`; live 94% macro forecast; credentials stripped from public files.

## 2026-09-11 · v1.x
- Early auto-sync builds — static board, first public deployment.

## v3.3.2 — Oct 9, 2026
- Threshold Watch collapsed by default (tap to open); red warning styling kept
- Watch body restructured into labeled sections with subheads; expiry line under the title

## v3.3.3 — Oct 9, 2026
- Masthead rebuilt in legacy Command Dashboard style: Live Telemetry badge + midterm clock chips, large title with gold accent, updated stamp
