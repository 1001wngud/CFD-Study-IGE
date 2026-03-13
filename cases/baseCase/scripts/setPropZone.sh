#!/usr/bin/env bash
set -euo pipefail

# usage: ./scripts/setPropZone.sh <h_m> [R_m] [t_m]
h="${1:?usage: $0 <h_m> [R_m] [t_m]}"
R="${2:-0.25}"
t="${3:-0.05}"

z1=$(awk -v h="$h" -v t="$t" 'BEGIN{printf "%.6f", h - t/2}')
z2=$(awk -v h="$h" -v t="$t" 'BEGIN{printf "%.6f", h + t/2}')

cat > system/createZonesDict <<EOF2
FoamFile
{
    version     2.0;
    format      ascii;
    class       dictionary;
    object      createZonesDict;
}

propeller
{
    type        cylinder;
    zoneType    cell;

    point1      (0 0 ${z1});
    point2      (0 0 ${z2});
    radius      ${R};
}
EOF2

createZones -clear | tee log.createZones
echo "[OK] propeller cellZone regenerated at h=${h} m (R=${R}, t=${t})"
