#!/usr/bin/env bash
set -euo pipefail

export FOAM_RUN=/home/joo/OpenFOAM/joo-13/run
export PROJ=$FOAM_RUN/trackB_propellerIGE_v13
export SWEEP=$PROJ/cases/sweep_baselineHover

DAY7="$SWEEP/day7_sweep_summary.csv"
DAY9="$SWEEP/day9_outwash_summary.csv"
OUTCSV="$SWEEP/day10_final_table.csv"
OUTQC="$SWEEP/day10_qc_report.txt"

if [[ ! -f "$DAY7" ]]; then
    echo "[ERROR] missing $DAY7"
    exit 1
fi

if [[ ! -f "$DAY9" ]]; then
    echo "[ERROR] missing $DAY9"
    exit 1
fi

python3 "$PROJ/scripts/day10_join_day7_day9.py" \
    --day7 "$DAY7" \
    --day9 "$DAY9" \
    --out-csv "$OUTCSV" \
    --out-qc "$OUTQC"

echo
echo "Preview:"
sed -n '1,20p' "$OUTCSV"
echo
echo "QC:"
sed -n '1,80p' "$OUTQC"
