#!/usr/bin/env bash
# Round-trip of test-files/ (the five JPEGs and the JPEG-LS file) with the
# packJPG binary given, on whatever slice this Mac runs. Counts the passes:
# an empty or skipped loop must not look green.
set -euo pipefail
BIN=$1
T=$(mktemp -d)
echo "$(uname -m): $BIN"
n=0
for f in test-files/*.jpg test-files/grayscale.jls; do
  b=$(basename "$f"); stem="${b%.*}"
  "$BIN" a -np -o -od"$T" "$f"
  mkdir -p "$T/x" && "$BIN" x -np -o -od"$T/x" "$T/${stem}.pjg"
  cmp "$f" "$T/x/$b" && echo "PASS: $f" && n=$((n+1))
done
[ "$n" -eq 6 ] || { echo "FAIL: $n of 6"; exit 1; }
