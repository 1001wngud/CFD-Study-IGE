#!/usr/bin/env bash
set -euo pipefail

# usage:
#   ./scripts/scanN.sh [caseDir] [endTime] [window] [n1 n2 ...]
# example:
#   ./scripts/scanN.sh . 80 30 10 12 15 18 26

caseDir="${1:-.}"
endTime="${2:-80}"
window="${3:-30}"
shift 3 || true

if [ "$#" -gt 0 ]; then
  nList=("$@")
else
  nList=(10 12 15 18 26)
fi

cd "$caseDir"
mkdir -p logs/day5/nScan
mkdir -p results

origControl="$(mktemp)"
origFvModels="$(mktemp)"
cp system/controlDict "$origControl"
cp constant/fvModels "$origFvModels"

origRefJson="$(mktemp)"
origRefCsv="$(mktemp)"
hadRefJson=0
hadRefCsv=0
if [ -f results/ref.json ]; then
  cp results/ref.json "$origRefJson"
  hadRefJson=1
fi
if [ -f results/ref.csv ]; then
  cp results/ref.csv "$origRefCsv"
  hadRefCsv=1
fi

cleanup() {
  cp "$origControl" system/controlDict
  cp "$origFvModels" constant/fvModels
  if [ "$hadRefJson" -eq 1 ]; then
    cp "$origRefJson" results/ref.json
  else
    rm -f results/ref.json
  fi
  if [ "$hadRefCsv" -eq 1 ]; then
    cp "$origRefCsv" results/ref.csv
  else
    rm -f results/ref.csv
  fi
  rm -f "$origControl" "$origFvModels" "$origRefJson" "$origRefCsv"
}
trap cleanup EXIT

set_control_for_scan() {
  perl -0777 -i -pe 's/(startFrom\s+).*(;)/${1}startTime${2}/' system/controlDict
  perl -0777 -i -pe 's/(startTime\s+).*(;)/${1}0${2}/' system/controlDict
  perl -0777 -i -pe 's/(endTime\s+).*(;)/${1}'"$endTime"'${2}/' system/controlDict
  perl -0777 -i -pe 's/(writeInterval\s+).*(;)/${1}20${2}/' system/controlDict
}

set_n_value() {
  local n="$1"
  perl -0777 -i -pe 's/(\bn\s+)[0-9.eE+-]+(\s*;)/${1}'"$n"'${2}/' constant/fvModels
}

clean_case_outputs() {
  find . -maxdepth 1 -type d -regextype posix-egrep -regex './[0-9]+(\.[0-9]+)?' -not -name '0' -exec rm -rf {} +
  rm -rf postProcessing
}

run_one() {
  local n="$1"
  echo "=== n=${n} (1/s), endTime=${endTime} ==="

  cp "$origFvModels" constant/fvModels
  set_n_value "$n"
  set_control_for_scan
  clean_case_outputs

  foamRun 2>&1 | tee "logs/day5/nScan/foamRun_n${n}_0to${endTime}.log" >/dev/null
  ./scripts/day5Diagnostics.sh . "$window" | tee "logs/day5/nScan/diag_n${n}.txt" >/dev/null
  ./scripts/extractRef.sh . 4 "$window" | tee "logs/day5/nScan/ref_n${n}.txt" >/dev/null

  cp results/ref.json "logs/day5/nScan/ref_n${n}.json"
  cp results/ref.csv "logs/day5/nScan/ref_n${n}.csv"

  echo "-- diag summary (n=${n}) --"
  grep -E "^J range:|^Jcorr range:|^T/rho mean=|^Q/rho mean=" "logs/day5/nScan/diag_n${n}.txt"
  grep -E "^status=|^T_over_rho=|^J_window|^Jcorr_window" "logs/day5/nScan/ref_n${n}.txt"
  echo
}

for n in "${nList[@]}"; do
  run_one "$n"
done

echo "Done. Scan artifacts: logs/day5/nScan/"
