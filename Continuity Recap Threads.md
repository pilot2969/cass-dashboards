- 2026-09-27: Deploy echo can lie — an earlier deploy printed "No changes to push" while a commit landed at the same minute (ba4666c). Rule: verify pushes via the GitHub API / live URL, never trust the script echo alone. Also: PAT health-check must read github.token / staging.github.token files directly — grepping the script for the token string returns empty and produces false 401s.
- 2026-09-27: Deploy with missing Daily Read went out staged with the old (09-26) read; evening-wire runs must regenerate Daily Read.md BEFORE deploying. Sequence for future sessions: read today's ledger entries → write Daily Read.md → deploy staging → verify → --prod → verify.
- 2026-11-19: Morning wire published at 09:38 ET — 8 cards (summit/Kremlin agenda + third Crimean bridge strike + €45bn reparations-contingent loan; Hegseth US-Venezuela partnership in Caracas + Essequibo trial balloon; patch-surge as the clusters
first
common
cause
vs
NSAs own outage + Chase still unassigned day 3; Houthi strike on Saudi sovereign wealth fund HQ; Greenland security deal ratified — card REFUSED a score, basing is the excluded case, annex list is the open question; Anthropic $1.5tn IPO beside Oregon v OpenAI + Fed hike talk; ICJ Myanmar merits finding; Alaska split Senate/House). Postdeploy 167 pass / 0 FAIL / 1 declared anchor warn. Ledger + journal + 2 pass-2 class gaps filed (Korea enrichment; Denver court-order violation with no sanction). Open: Chase cause, Greenland annexes, whether a joint text names Ukraine.
