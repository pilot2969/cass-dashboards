#!/bin/bash
# Day-roll for the Daily Read: archive yesterday's stacked edition, reset for today.
cd "$(dirname "$0")"
Y=$(date -d yesterday +%F)
T=$(date +%F)
if [ -f "Daily Read.md" ] && [ ! -f "archive/Daily Read $Y.md" ]; then
  mkdir -p archive
  cp "Daily Read.md" "archive/Daily Read $Y.md"
  printf '# The Daily Read — %s\n\n**Rolling edition — stories stack as the wire runs all day. Archived at the start of the next day.**\n\n(no sections filed yet — first wire run of the day writes the morning edition)\n' "$T" > "Daily Read.md"
  ./sync_data.sh "day-roll $Y archived; Daily Read reset for $T"
fi
