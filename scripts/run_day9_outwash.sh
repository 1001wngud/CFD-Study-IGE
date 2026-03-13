#!/usr/bin/env bash
set -euo pipefail

export FOAM_RUN=/home/joo/OpenFOAM/joo-13/run
export PROJ=$FOAM_RUN/trackB_propellerIGE_v13
export SWEEP=$PROJ/cases/sweep_baselineHover

CASES=(hR4 hR2 hR1 hR0p5 hR0p35)

RADIUS=0.25
X0=0.0
Y0=0.0
NBINS=120
MINCOUNT=1

Z_CANDIDATES=(0.01 0.005 0.02)

FO_NAME=outwashSurfaces
PLANE_NAME=groundPlane

summary_csv="$SWEEP/day9_outwash_summary.csv"
mkdir -p "$SWEEP"

python3 - <<'PY' "$summary_csv"
import csv
import sys

path = sys.argv[1]
with open(path, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(
        [
            "case",
            "h_over_R",
            "z_plane_m",
            "rmax_m",
            "rmax_R",
            "vr_peak_mps",
            "n_points",
            "valid_bins",
            "status",
            "note",
            "source_xy",
        ]
    )
PY

case_to_hR() {
    case "$1" in
        hR4) echo "4" ;;
        hR2) echo "2" ;;
        hR1) echo "1" ;;
        hR0p5) echo "0.5" ;;
        hR0p35) echo "0.35" ;;
        *) echo "" ;;
    esac
}

write_dict() {
    local z="$1"
    local dict_path="$2"
    python3 - <<'PY' "$dict_path" "$FO_NAME" "$PLANE_NAME" "$X0" "$Y0" "$z"
import sys

path, fo_name, plane_name, x0, y0, z = sys.argv[1:7]

text = f"""FoamFile
{{
    format      ascii;
    class       dictionary;
    object      day9_outwashDict;
}}

{fo_name}
{{
    type                surfaces;
    libs                (\"libsampling.so\");

    writeControl        writeTime;

    surfaceFormat       raw;
    fields              (U);
    interpolationScheme cellPoint;

    surfaces
    (
        {plane_name}
        {{
            type        cuttingPlane;
            planeType   pointAndNormal;

            pointAndNormalDict
            {{
                point   ({x0} {y0} {z});
                normal  (0 0 1);
            }}

            interpolate true;
        }}
    );
}}
"""

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

append_row() {
    local case_name="$1"
    local hR="$2"
    local json_path="$3"

    python3 - <<'PY' "$summary_csv" "$case_name" "$hR" "$json_path"
import csv
import json
import sys

summary_csv, case_name, hR, json_path = sys.argv[1:5]

if json_path == "__FAIL_NO_JSON__":
    row = [case_name, hR, "", "", "", "", "", "", "fail_no_json", "summary json not created", ""]
else:
    with open(json_path, "r", encoding="utf-8") as f:
        d = json.load(f)

    peak = d.get("peak") or {}
    row = [
        case_name,
        hR,
        d.get("z_plane_m", ""),
        peak.get("rmax_m", ""),
        peak.get("rmax_R", ""),
        peak.get("vr_peak_mps", ""),
        d.get("n_points", ""),
        d.get("valid_bins", ""),
        d.get("status", ""),
        d.get("note", ""),
        d.get("xy_path", ""),
    ]

with open(summary_csv, "a", newline="", encoding="utf-8") as f:
    csv.writer(f).writerow(row)
PY
}

for c in "${CASES[@]}"; do
    case_dir="$SWEEP/$c"
    hR=$(case_to_hR "$c")

    echo "=== Day9: $c (h/R=$hR) ==="
    cd "$case_dir"
    mkdir -p results

    final_json=""
    success=0

    for z in "${Z_CANDIDATES[@]}"; do
        ztag=${z//./p}
        dict_path="results/day9_outwashDict"

        rm -rf "postProcessing/${FO_NAME}"
        write_dict "$z" "$dict_path"

        log1="results/day9_${FO_NAME}_z${ztag}.log"

        foamPostProcess \
            -solver incompressibleFluid \
            -latestTime \
            -dict "$dict_path" \
            > "$log1" 2>&1 || true

        xy_file=$(find "postProcessing/${FO_NAME}" -type f -name "${PLANE_NAME}.xy" 2>/dev/null | sort -V | tail -n 1 || true)

        if [[ -z "${xy_file}" ]]; then
            echo "  [WARN] z=${z}: ${PLANE_NAME}.xy 없음"
            continue
        fi

        out_prefix="results/day9_outwash_z${ztag}"

        python3 "$PROJ/scripts/day9_extract_outwash_rmax.py" \
            --xy "$xy_file" \
            --x0 "$X0" \
            --y0 "$Y0" \
            --R "$RADIUS" \
            --z-plane "$z" \
            --nbins "$NBINS" \
            --min-count "$MINCOUNT" \
            --out-prefix "$out_prefix" \
            | tee "results/day9_extract_z${ztag}.stdout.json"

        json_path="${out_prefix}_summary.json"
        if [[ ! -f "$json_path" ]]; then
            echo "  [WARN] z=${z}: summary json 없음"
            continue
        fi

        status=$(python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    d = json.load(f)
print(d.get("status", ""))
PY
)

        echo "  status=$status"

        case "$status" in
            ok|warn_edge_peak|warn_sparse_bins)
                final_json="$json_path"
                success=1
                break
                ;;
            *)
                ;;
        esac
    done

    if [[ "$success" -eq 1 ]]; then
        append_row "$c" "$hR" "$final_json"
    else
        append_row "$c" "$hR" "__FAIL_NO_JSON__"
    fi
done

echo
echo "DONE: $summary_csv"
