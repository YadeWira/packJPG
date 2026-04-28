#!/bin/bash
# bench.sh v2 - SITX vs packJPG ratio + speed test (fixes path + ext bugs)
# Usage:   ./bench.sh ./jpgs
# Output:  stdout (save with > results.txt)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITX="$SCRIPT_DIR/sitx"
PJG="$SCRIPT_DIR/packJPG"

[ ! -x "$SITX" ] && { echo "ERROR: $SITX not found or not executable"; exit 1; }
[ ! -x "$PJG"  ] && { echo "ERROR: $PJG not found or not executable"; exit 1; }

if ! grep -qw avx2 /proc/cpuinfo; then
    echo "WARNING: This CPU lacks AVX2 - SITX will SIGILL." >&2
fi

JPGS_DIR="${1:-./jpgs}"
[ ! -d "$JPGS_DIR" ] && { echo "ERROR: dir $JPGS_DIR not found"; exit 1; }
JPGS_DIR="$(cd "$JPGS_DIR" && pwd)"   # absolute path so cd doesn't break refs

shopt -s nullglob
JPGS=( "$JPGS_DIR"/*.jpg "$JPGS_DIR"/*.jpeg "$JPGS_DIR"/*.JPG "$JPGS_DIR"/*.JPEG )
shopt -u nullglob
[ ${#JPGS[@]} -eq 0 ] && { echo "ERROR: no JPGs in $JPGS_DIR"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

strip_jpg_ext() {
    local f="$1"
    case "$f" in
        *.jpg)  echo "${f%.jpg}";;
        *.JPG)  echo "${f%.JPG}";;
        *.jpeg) echo "${f%.jpeg}";;
        *.JPEG) echo "${f%.JPEG}";;
        *)      echo "$f";;
    esac
}

total_orig=0; total_sitx=0; total_pjg=0
total_t_sitx=0; total_t_pjg=0
cnt=0; sitx_errs=0; pjg_errs=0

printf "%-50s %10s %10s %10s %8s %8s\n" "file" "orig" "sitx" "packjpg" "delta%" "winner"
echo "-----------------------------------------------------------------------------------------------------"

for jpg in "${JPGS[@]}"; do
    [ ! -f "$jpg" ] && continue
    name=$(basename "$jpg")
    orig=$(stat -c%s "$jpg")
    [ "$orig" -lt 100 ] && continue

    rm -f "$WORK/out.enc"
    cd "$WORK"
    t0=$(date +%s%N)
    "$SITX" 2 "$jpg" >/dev/null 2>&1 && sitx_ok=1 || sitx_ok=0
    t_sitx=$(( ($(date +%s%N) - t0) / 1000000 ))
    sitx_sz=0
    [ -f "$WORK/out.enc" ] && [ "$sitx_ok" = "1" ] && sitx_sz=$(stat -c%s "$WORK/out.enc")
    cd - >/dev/null

    pjg_workdir="$WORK/pjg_work"
    rm -rf "$pjg_workdir"; mkdir -p "$pjg_workdir"
    cp "$jpg" "$pjg_workdir/"
    pjg_in="$pjg_workdir/$name"
    pjg_base="$(strip_jpg_ext "$pjg_in")"
    pjg_out="${pjg_base}.pjg"
    rm -f "$pjg_out"
    t0=$(date +%s%N)
    "$PJG" a -np -o "$pjg_in" >/dev/null 2>&1 && pjg_ok=1 || pjg_ok=0
    t_pjg=$(( ($(date +%s%N) - t0) / 1000000 ))
    pjg_sz=0
    [ -f "$pjg_out" ] && [ "$pjg_ok" = "1" ] && pjg_sz=$(stat -c%s "$pjg_out")

    if [ "$sitx_sz" -gt 0 ] && [ "$pjg_sz" -gt 0 ]; then
        delta=$(awk "BEGIN{printf \"%+.2f\", ($sitx_sz - $pjg_sz) * 100.0 / $pjg_sz}")
        if [ "$sitx_sz" -lt "$pjg_sz" ]; then winner="SITX"
        elif [ "$pjg_sz" -lt "$sitx_sz" ]; then winner="packJPG"
        else winner="tie"; fi
    else
        delta="N/A"
        if [ "$sitx_sz" = "0" ] && [ "$pjg_sz" = "0" ]; then winner="both_err"; sitx_errs=$((sitx_errs+1)); pjg_errs=$((pjg_errs+1))
        elif [ "$sitx_sz" = "0" ]; then sitx_errs=$((sitx_errs+1)); winner="sitx_err"
        else pjg_errs=$((pjg_errs+1)); winner="pjg_err"; fi
    fi

    printf "%-50s %10d %10d %10d %8s %8s\n" "${name:0:50}" "$orig" "$sitx_sz" "$pjg_sz" "$delta" "$winner"

    total_orig=$((total_orig + orig))
    [ "$sitx_sz" -gt 0 ] && total_sitx=$((total_sitx + sitx_sz))
    [ "$pjg_sz"  -gt 0 ] && total_pjg=$((total_pjg + pjg_sz))
    total_t_sitx=$((total_t_sitx + t_sitx))
    total_t_pjg=$((total_t_pjg + t_pjg))
    cnt=$((cnt + 1))
done

echo "-----------------------------------------------------------------------------------------------------"
echo "Summary on $cnt files (sitx errors: $sitx_errs, packjpg errors: $pjg_errs):"
awk -v o=$total_orig -v s=$total_sitx -v p=$total_pjg -v ts=$total_t_sitx -v tp=$total_t_pjg 'BEGIN{
    printf "  Total input:  %d bytes (%.2f MB)\n", o, o/1048576
    if (s>0) printf "  SITX total:   %d bytes  (%.2f%% of input, %d ms)\n", s, s*100/o, ts
    if (p>0) printf "  packJPG:      %d bytes  (%.2f%% of input, %d ms)\n", p, p*100/o, tp
    if (s>0 && p>0) {
        printf "  Delta ratio:  %+.2f%% (SITX vs packJPG; negative = SITX smaller)\n", (s - p) * 100.0 / p
        printf "  Speed ratio:  %.2fx (SITX time / packJPG time; <1 = SITX faster)\n", ts / tp
    }
}'
