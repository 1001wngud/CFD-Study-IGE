#!/usr/bin/env bash
set -euo pipefail

# Day8 sensitivity runbook (A: baseline flat low-J, B: tilted low-J)
# Safe defaults:
# - Never edit baseCase_baselineHover
# - Work only in sweep_sensitivity_lowJtilt
# - Preserve 0/ folder during cleanup

FOAM_RUN="${FOAM_RUN:-/home/joo/OpenFOAM/joo-13/run}"
PROJ="${PROJ:-$FOAM_RUN/trackB_propellerIGE_v13}"
SWEEP_A="${SWEEP_A:-$PROJ/cases/sweep_baselineHover}"
SWEEP_B="${SWEEP_B:-$PROJ/cases/sweep_sensitivity_lowJtilt}"
REF_JSON="${REF_JSON:-$PROJ/cases/baseCase_baselineHover/results/ref_final_baselineHover.json}"

# Default subset for Day8 (fast and sufficient)
cases=(hR1 hR0p5)
R=0.25
t=0.05
delta="${DELTA:-0.08}"

hr_of_case() {
  case "$1" in
    hR4) echo 4 ;;
    hR2) echo 2 ;;
    hR1) echo 1 ;;
    hR0p5) echo 0.5 ;;
    hR0p35) echo 0.35 ;;
    *) echo "ERROR: unknown case '$1'" >&2; exit 1 ;;
  esac
}

h_of_case() {
  case "$1" in
    hR4) echo 1.0 ;;
    hR2) echo 0.5 ;;
    hR1) echo 0.25 ;;
    hR0p5) echo 0.125 ;;
    hR0p35) echo 0.0875 ;;
    *) echo "ERROR: unknown case '$1'" >&2; exit 1 ;;
  esac
}

echo "[INFO] PROJ=$PROJ"
echo "[INFO] SWEEP_A=$SWEEP_A"
echo "[INFO] SWEEP_B=$SWEEP_B"
echo "[INFO] REF_JSON=$REF_JSON"

test -f "$REF_JSON" || { echo "ERROR: ref json missing: $REF_JSON"; exit 1; }
test -f "$SWEEP_A/day7_sweep_summary.csv" || { echo "ERROR: missing $SWEEP_A/day7_sweep_summary.csv"; exit 1; }

mkdir -p "$SWEEP_B"

# 1) Clone A -> B (do NOT exclude 0/)
for c in "${cases[@]}"; do
  src="$SWEEP_A/$c"
  dst="$SWEEP_B/$c"
  test -d "$src" || { echo "ERROR: missing source case $src"; exit 1; }
  rm -rf "$dst"
  rsync -a --delete "$src/" "$dst/"
done

# 2) Patch low-J curve in B
for c in "${cases[@]}"; do
  cd "$SWEEP_B/$c"
  cp -a constant/fvModels constant/fvModels.day8B.bak

  python3 - <<PY
import re
fn="constant/fvModels"
delta=float("$delta")
txt=open(fn,"r",encoding="utf-8",errors="ignore").read()

# Accept 0.1 or 0.10 style
m=re.search(r'\(\s*0\.1(?:0+)?\s*\(\s*([0-9.eE+-]+)\s+([0-9.eE+-]+)\s*\)\s*\)', txt)
if not m:
    raise SystemExit("ERROR: J=0.10 row not found")
Kt10=float(m.group(1)); Kq10=float(m.group(2))
Kt0=Kt10*(1.0+delta); Kq0=Kq10*(1.0+delta)
Kt05=0.5*(Kt10+Kt0); Kq05=0.5*(Kq10+Kq0)

targets={
    "-0.50": (Kt0, Kq0),
    "-0.25": (Kt0, Kq0),
    "0.00":  (Kt0, Kq0),
    "0.05":  (Kt05, Kq05),
}

def repl(j,kt,kq,s):
    pat=rf'\(\s*{re.escape(j)}\s*\(\s*[0-9.eE+-]+\s+[0-9.eE+-]+\s*\)\s*\)'
    new=f'({j} ({kt:.6f} {kq:.6f}))'
    s2,n=re.subn(pat,new,s,count=1)
    if n!=1:
        raise SystemExit(f"ERROR: row for J={j} matched {n} times")
    return s2

for j,(kt,kq) in targets.items():
    txt=repl(j,kt,kq,txt)

open(fn,"w",encoding="utf-8").write(txt)
print(f"OK {fn} Kt10={Kt10:.6f} Kq10={Kq10:.6f} -> Kt0={Kt0:.6f} Kq0={Kq0:.6f}")
PY

  rg -n "outOfBounds|\(-0\.50|\(-0\.25|\(0\.00|\(0\.05|\(0\.10" constant/fvModels || true
  cd "$SWEEP_B"
done

# 3) Zone refresh + clean start (preserve 0/)
for c in "${cases[@]}"; do
  cd "$SWEEP_B/$c"
  h="$(h_of_case "$c")"

  ./scripts/setPropZone.sh "$h" "$R" "$t"
  createZones -clear | tee log.day8_createZones.txt >/dev/null

  # Keep 0/, delete only numeric time dirs > 0
  find . -maxdepth 1 -type d -regextype posix-egrep -regex './[0-9]+(\.[0-9]+)?' -not -name '0' -exec rm -rf {} +
  rm -rf postProcessing

  foamDictionary -entry startFrom -set startTime system/controlDict >/dev/null
  foamDictionary -entry startTime -set 0 system/controlDict >/dev/null
  foamDictionary -entry endTime -set 1000 system/controlDict >/dev/null

done

# 4) Run + diagnostics/extract
for c in "${cases[@]}"; do
  cd "$SWEEP_B/$c"
  hr="$(hr_of_case "$c")"
  mkdir -p results

  foamRun 2>&1 | tee log.day8B_run_end1000.txt >/dev/null
  ./scripts/day5Diagnostics.sh . 100 | tee results/day8B_diag_window100.txt >/dev/null
  ./scripts/extractRef.sh . "$hr" 100 | tee results/day8B_extract_window100.txt >/dev/null

  echo "=== GATE $c ==="
  grep -E "^status=|outOfRange|^J_window|^Jcorr_window|^T_over_rho=" results/day8B_extract_window100.txt || true
done

# 5) Build B summary
cd "$SWEEP_B"
Tref=$(python3 - <<PY
import json
print(json.load(open("$REF_JSON"))["T_over_rho"])
PY
)
Pref=$(python3 - <<PY
import json
print(json.load(open("$REF_JSON"))["P_over_rho"])
PY
)

outB="day8B_sweep_summary.csv"
echo "case,h_over_R,T_over_rho,Q_over_rho,P_over_rho,T_Tref,P_Pref" > "$outB"
for c in "${cases[@]}"; do
  hr="$(hr_of_case "$c")"
  f="$SWEEP_B/$c/results/day8B_extract_window100.txt"
  line=$(grep -E '^T_over_rho=' "$f" | tail -n 1)
  T=$(echo "$line" | awk '{print $1}' | cut -d= -f2)
  Q=$(echo "$line" | awk '{print $2}' | cut -d= -f2)
  P=$(echo "$line" | awk '{print $3}' | cut -d= -f2)

  TT=$(awk -v a="$T" -v b="$Tref" 'BEGIN{printf "%.8f", a/b}')
  PP=$(awk -v a="$P" -v b="$Pref" 'BEGIN{printf "%.8f", a/b}')

  echo "$c,$hr,$T,$Q,$P,$TT,$PP" >> "$outB"
done

# 6) Compare A vs B (FIXED: A columns are 6=T_Tref, 7=P_Pref)
A="$SWEEP_A/day7_sweep_summary.csv"
B="$SWEEP_B/day8B_sweep_summary.csv"
cmp="day8_compare_A_vs_B.csv"
unc="day8_uncertainty_band.csv"

awk -F, '
BEGIN{OFS=","}
FNR==1{next}
FILENAME==ARGV[1]{
  hr=$2
  A_TT[hr]=$6
  A_PP[hr]=$7
  next
}
{
  hr=$2
  B_TT[hr]=$6
  B_PP[hr]=$7
}
END{
  print "h_over_R,A_T_Tref,B_T_Tref,deltaT_pct,A_P_Pref,B_P_Pref,deltaP_pct" > "'"$cmp"'"
  for (hr in B_TT){
    aT=A_TT[hr]+0; bT=B_TT[hr]+0
    aP=A_PP[hr]+0; bP=B_PP[hr]+0
    dT=(bT/aT-1.0)*100.0
    dP=(bP/aP-1.0)*100.0
    printf "%s,%.6f,%.6f,%.3f,%.6f,%.6f,%.3f\n", hr,aT,bT,dT,aP,bP,dP >> "'"$cmp"'"
  }
}' "$A" "$B"

awk -F, '
BEGIN{OFS=","}
FNR==1{next}
{
  hr=$1
  aT=$2+0; bT=$3+0
  aP=$5+0; bP=$6+0
  bandT=0.5*sqrt((bT-aT)*(bT-aT))/aT*100.0
  bandP=0.5*sqrt((bP-aP)*(bP-aP))/aP*100.0
  loT=(aT<bT?aT:bT); hiT=(aT>bT?aT:bT)
  loP=(aP<bP?aP:bP); hiP=(aP>bP?aP:bP)
  print hr,loT,hiT,bandT,loP,hiP,bandP
}' "$cmp" | awk 'BEGIN{print "h_over_R,T_range_low,T_range_high,T_pm_pct,P_range_low,P_range_high,P_pm_pct"} {print}' > "$unc"

echo
echo "== Day8 B summary =="
column -s, -t "$outB"
echo
echo "== A vs B compare =="
column -s, -t "$cmp"
echo
echo "== Uncertainty band =="
column -s, -t "$unc"

echo
echo "[DONE] Day8 sensitivity completed in $SWEEP_B"
