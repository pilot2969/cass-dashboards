#!/bin/bash
# Day-roll for the Daily Read: archive yesterday's stacked edition, reset for today.
cd "$(dirname "$0")"
Y=$(date -d yesterday +%F)
T=$(date +%F)
# Guard on the GENERATED html, not the source .md — build_archive.py converts
# editions to <slug>.html and removes nothing, so checking for the .md always
# failed and every run re-archived + reset the rolling file (2026-10-22 bug).
if [ -f "Daily Read.md" ] && [ -s "Daily Read.md" ] \
   && ! ls archive/daily-read-$Y-*.html >/dev/null 2>&1; then
  mkdir -p archive
  cp "Daily Read.md" "archive/Daily Read $Y.md"
  printf '# The Daily Read — %s\n\n**Rolling edition — stories stack as the wire runs all day. Archived at the start of the next day.**\n\n(no sections filed yet — first wire run of the day writes the morning edition)\n' "$T" > "Daily Read.md"
  ./sync_data.sh "day-roll $Y archived; Daily Read reset for $T"
fi
