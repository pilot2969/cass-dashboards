#!/bin/bash
# Day-roll for the Daily Read: archive the finished edition, reset for today.
# 2026-11-02 REWRITE: the old guard compared "yesterday" to the archive while the
# file it copied held TODAY's edition, so it fired mid-morning and wiped the day's
# cards (the 08:38 ET edition was destroyed at 08:48 in commit e17cca9 and the
# board fell back to an Oct 28 panel). New rule: never touch the file while the
# date inside it is today, and roll at most once per date.
cd "$(dirname "$0")"
T=$(date +%F)
MARK=".dayroll-$T"
if [ -f "$MARK" ]; then
  echo "day-roll: already rolled today ($T); nothing to do"
  exit 0
fi
[ -f "Daily Read.md" ] || { echo "day-roll: no Daily Read.md"; exit 0; }
INSIDE=$(grep -m1 -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "Daily Read.md" | head -1)
if [ -z "$INSIDE" ]; then
  echo "day-roll: no date inside the file; refusing to reset blind"
  exit 1
fi
if [ "$INSIDE" = "$T" ]; then
  echo "day-roll: file holds today's edition ($INSIDE); not rolling"
  touch "$MARK"
  exit 0
fi
mkdir -p archive
cp "Daily Read.md" "archive/Daily Read $INSIDE.md"
# 2026-11-13 FIX: the reset template carried the date ONLY in the title. Every
# downstream consumer (Publish Guard check 1, sync_data.sh line 201, build_archive.py)
# keys on a literal "DATE: YYYY-MM-DD" line, so a freshly reset file read as
# "edition MISSING" at 08:20 for three mornings running -- the reset itself created
# the failure it was blamed for. Write the machine-readable stamp in the template.
printf '# The Daily Read — %s\n\nDATE: %s\n\n**Rolling edition — stories stack as the wire runs all day. Archived at the start of the next day.**\n\n(no sections filed yet — first wire run of the day writes the morning edition)\n' "$T" "$T" > "Daily Read.md"
touch "$MARK"
./sync_data.sh "day-roll $INSIDE archived; Daily Read reset for $T"
