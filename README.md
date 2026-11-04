# CASS Dashboard — repo notes

Index of repo not needed here.

## Upload protocol (v3.11.0, 2026-11-04)

A push is a release. Five things move together:

| # | Artefact | Where | Checked by |
|---|---|---|---|
| 1 | Footer version | `Internal Telemetry.html` → `<span class="ftver">` | `docs.changelog` |
| 2 | Change log | page 📜 block **and** `CHANGELOG.md` | `docs.changelog` |
| 3 | Data Dictionary | every new field **and** every new interface term | `docs.dictionary` (fields only — terms are on the author) |
| 4 | Version consistency | footer = page change log = `CHANGELOG.md` = inline `// vX.Y.Z (date):` script comment | author |
| 5 | Gate | `prepush` → push → `postdeploy`, always **after** any pull | `verify_prod.js` |

```bash
# design change: staging only, report it as staging-only
STAGING_ONLY=1 ./sync_data.sh "vX.Y.Z: what changed and why it matters"

# promotion after owner sign-off: this run IS the release
./sync_data.sh "vX.Y.Z: promote to prod"
```

Semver here: minor bump for a new panel or new reading, patch for a fix, **no version change on a data-only run** (data.json, shards, history.json and the register only).

Never report a board as updated until the post-deploy gate is green. Pushed, deployed and verified are three different facts.

Full rule: `/space/protocol/prod-review-gate.json` and `/space/protocol/push-checklist.json`.
