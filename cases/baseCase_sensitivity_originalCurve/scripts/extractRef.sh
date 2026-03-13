#!/usr/bin/env bash
set -euo pipefail

# usage: ./scripts/extractRef.sh [caseDir] [hOverR] [window]
caseDir="${1:-.}"
hOverR="${2:-4}"
window="${3:-100}"

cd "$caseDir"
mkdir -p results

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

last="$(awk 'NF && $1 !~ /^#/ {line=$0} END{print line}' "$f")"
if [ -z "${last:-}" ]; then
  echo "ERROR: no data rows in $f"
  exit 1
fi

# Time(1) n(2) J(3) Jcorr(4) Udisk(5) Ucorr(6) Kt(7) Kq(8) T/rho(9) Q/rho(10)
read -r time n J Jcorr Udisk Ucorr Kt Kq T_over_rho Q_over_rho _ <<< "$last"
P_over_rho="$(awk -v n="$n" -v Q="$Q_over_rho" 'BEGIN{pi=atan2(0,-1); printf "%.12g", 2*pi*n*Q}')"

read -r jMinAllowed jMaxAllowed <<<"$(detect_j_bounds)"

read -r meanT relT meanQ relQ meanJ minJ maxJ outJ meanJcorr minJcorr maxJcorr outJcorr nWin <<< "$(
awk -v W="$window" -v JMIN="$jMinAllowed" -v JMAX="$jMaxAllowed" '
NF && $1 !~ /^#/ {t[++n]=$9; q[n]=$10; j[n]=$3; jc[n]=$4}
END{
  if (n==0) {print "NaN NaN NaN NaN NaN NaN NaN 0 NaN NaN NaN 0 0"; exit}
  N=W; if (n<N) N=n
  sumT=0; sumQ=0; sumJ=0; sumJc=0
  minT=1e99; maxT=-1e99; minQ=1e99; maxQ=-1e99
  minJ=1e99; maxJ=-1e99; out=0
  minJc=1e99; maxJc=-1e99; outJc=0
  for(i=n-N+1; i<=n; i++){
    T=t[i]; Q=q[i]; J=j[i]; Jc=jc[i]
    sumT+=T; sumQ+=Q; sumJ+=J; sumJc+=Jc
    if(T<minT) minT=T; if(T>maxT) maxT=T
    if(Q<minQ) minQ=Q; if(Q>maxQ) maxQ=Q
    if(J<minJ) minJ=J; if(J>maxJ) maxJ=J
    if(Jc<minJc) minJc=Jc; if(Jc>maxJc) maxJc=Jc
    if(J<JMIN || J>JMAX) out++
    if(Jc<JMIN || Jc>JMAX) outJc++
  }
  meanT=sumT/N; meanQ=sumQ/N; meanJ=sumJ/N; meanJc=sumJc/N
  relT=100*(maxT-minT)/meanT
  relQ=100*(maxQ-minQ)/meanQ
  printf "%.12g %.12g %.12g %.12g %.12g %.12g %.12g %d %.12g %.12g %.12g %d %d\n", meanT, relT, meanQ, relQ, meanJ, minJ, maxJ, out, meanJc, minJc, maxJc, outJc, N
}' "$f"
)"

status="ok"
if [ "$outJ" -gt 0 ] || [ "$outJcorr" -gt 0 ]; then
  status="provisional_j_bounds_out_of_range"
fi

cat > results/ref.json <<JSON
{
  "case": "$(pwd)",
  "sourceFile": "$f",
  "hOverR": $hOverR,
  "time": $time,
  "n": $n,
  "T_over_rho": $T_over_rho,
  "Q_over_rho": $Q_over_rho,
  "P_over_rho": $P_over_rho,
  "J_allowed_min": $jMinAllowed,
  "J_allowed_max": $jMaxAllowed,
  "window": $nWin,
  "T_over_rho_mean_window": $meanT,
  "T_over_rho_relRange_pct_window": $relT,
  "Q_over_rho_mean_window": $meanQ,
  "Q_over_rho_relRange_pct_window": $relQ,
  "J_mean_window": $meanJ,
  "J_min_window": $minJ,
  "J_max_window": $maxJ,
  "J_outOfRange_window_count": $outJ,
  "Jcorr_mean_window": $meanJcorr,
  "Jcorr_min_window": $minJcorr,
  "Jcorr_max_window": $maxJcorr,
  "Jcorr_outOfRange_window_count": $outJcorr,
  "status": "$status"
}
JSON

cat > results/ref.csv <<CSV
hOverR,time,n,T_over_rho,Q_over_rho,P_over_rho,J_allowed_min,J_allowed_max,T_mean_win,T_relRange_pct_win,Q_mean_win,Q_relRange_pct_win,J_mean_win,J_min_win,J_max_win,J_outOfRange_win_count,Jcorr_mean_win,Jcorr_min_win,Jcorr_max_win,Jcorr_outOfRange_win_count,status
$hOverR,$time,$n,$T_over_rho,$Q_over_rho,$P_over_rho,$jMinAllowed,$jMaxAllowed,$meanT,$relT,$meanQ,$relQ,$meanJ,$minJ,$maxJ,$outJ,$meanJcorr,$minJcorr,$maxJcorr,$outJcorr,$status
CSV

echo "logFile=$f"
echo "time=$time n=$n"
echo "T_over_rho=$T_over_rho Q_over_rho=$Q_over_rho P_over_rho=$P_over_rho"
echo "J_allowed_min=$jMinAllowed J_allowed_max=$jMaxAllowed"
echo "window=$nWin T_relRange_pct=$relT Q_relRange_pct=$relQ"
echo "J_window min=$minJ max=$maxJ outOfRange=$outJ/$nWin"
echo "Jcorr_window min=$minJcorr max=$maxJcorr outOfRange=$outJcorr/$nWin"
echo "status=$status"
echo "Wrote: results/ref.json, results/ref.csv"
