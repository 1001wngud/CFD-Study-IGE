#!/usr/bin/env bash
set -euo pipefail

# usage: ./scripts/day5Diagnostics.sh [caseDir] [window]
caseDir="${1:-.}"
window="${2:-50}"

cd "$caseDir"

detect_j_bounds() {
  local dict="constant/fvModels"
  if [ ! -f "$dict" ]; then
    echo "0.10 0.80"
    return
  fi

  awk '
  /^[[:space:]]*\([+-]?[0-9]/ {
    line = $0
    sub(/^[[:space:]]*\(/, "", line)
    split(line, a, /[^0-9eE+.-]+/)
    x = a[1] + 0
    if (!init) {min = x; max = x; init = 1}
    if (x < min) min = x
    if (x > max) max = x
  }
  END {
    if (init) printf "%.12g %.12g\n", min, max
    else print "0.10 0.80"
  }' "$dict"
}

pick_latest_propeller_log() {
  local bestFile=""
  local bestTime="-1"
  while IFS= read -r cand; do
    [ -f "$cand" ] || continue
    local t
    t="$(awk 'NF && $1 !~ /^#/ {last=$1} END{if(last=="") print -1; else print last}' "$cand")"
    if awk -v t="$t" -v b="$bestTime" 'BEGIN{exit !(t>b)}'; then
      bestTime="$t"
      bestFile="$cand"
    fi
  done < <(find postProcessing -type f -name 'propellerDisk.dat')
  echo "$bestFile"
}

f="$(pick_latest_propeller_log)"
if [ -z "${f:-}" ] || [ ! -f "$f" ]; then
  echo "ERROR: propellerDisk.dat not found under postProcessing/"
  exit 1
fi

echo "=== propellerDisk source ==="
echo "file: $f"
read -r jMinAllowed jMaxAllowed <<<"$(detect_j_bounds)"
echo "J bounds from fvModels: [$jMinAllowed, $jMaxAllowed]"

echo
echo "=== last ${window} rows: time n J Jcorr Kt Kq T/rho Q/rho ==="
awk -v W="$window" '
NF && $1 !~ /^#/ {line[++n]=$0}
END{
  if (n==0) exit
  s=n-W+1; if (s<1) s=1
  for(i=s;i<=n;i++){
    split(line[i], a, /[[:space:]]+/)
    printf "%s %s %s %s %s %s %s %s\n", a[1], a[2], a[3], a[4], a[7], a[8], a[9], a[10]
  }
}' "$f"

echo
echo "=== window summary (${window}) ==="
awk -v W="$window" -v JMIN="$jMinAllowed" -v JMAX="$jMaxAllowed" '
NF && $1 !~ /^#/ {
  j[++n]=$3; jc[n]=$4; kt[n]=$7; kq[n]=$8; t[n]=$9; q[n]=$10
}
END{
  if (n==0) {
    print "no data"
    exit
  }
  N=W; if (n<N) N=n
  minJ=1e99; maxJ=-1e99; outJ=0
  minJc=1e99; maxJc=-1e99; outJc=0
  minKt=1e99; maxKt=-1e99
  minKq=1e99; maxKq=-1e99
  minT=1e99; maxT=-1e99; sumT=0
  minQ=1e99; maxQ=-1e99; sumQ=0
  for(i=n-N+1; i<=n; i++){
    J=j[i]; Jc=jc[i]; Kt=kt[i]; Kq=kq[i]; T=t[i]; Q=q[i]
    if (J<minJ) minJ=J; if (J>maxJ) maxJ=J
    if (Jc<minJc) minJc=Jc; if (Jc>maxJc) maxJc=Jc
    if (J<JMIN || J>JMAX) outJ++
    if (Jc<JMIN || Jc>JMAX) outJc++
    if (Kt<minKt) minKt=Kt; if (Kt>maxKt) maxKt=Kt
    if (Kq<minKq) minKq=Kq; if (Kq>maxKq) maxKq=Kq
    if (T<minT) minT=T; if (T>maxT) maxT=T
    if (Q<minQ) minQ=Q; if (Q>maxQ) maxQ=Q
    sumT+=T; sumQ+=Q
  }
  meanT=sumT/N; meanQ=sumQ/N
  relT=100*(maxT-minT)/meanT
  relQ=100*(maxQ-minQ)/meanQ
  printf "J range:     [%g, %g], out-of-range: %d/%d\n", minJ, maxJ, outJ, N
  printf "Jcorr range: [%g, %g], out-of-range: %d/%d\n", minJc, maxJc, outJc, N
  printf "Kt range:    [%g, %g]\n", minKt, maxKt
  printf "Kq range:    [%g, %g]\n", minKq, maxKq
  printf "T/rho mean=%g, relRange=%g%%\n", meanT, relT
  printf "Q/rho mean=%g, relRange=%g%%\n", meanQ, relQ
}' "$f"

echo
echo "=== functionObject traces (latest file tail) ==="
for fo in Uavg_propeller phi_farField phi_top; do
  d="postProcessing/${fo}"
  if [ -d "$d" ]; then
    lf="$(find "$d" -type f | sort | tail -n 1)"
    echo "--- $fo"
    echo "file: $lf"
    tail -n 8 "$lf"
  else
    echo "--- $fo: no postProcessing directory yet"
  fi
done
