#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


REQUIRED_CASES = ["hR4", "hR2", "hR1", "hR0p5", "hR0p35"]


def norm(s):
    return "".join(ch.lower() for ch in s.strip() if ch.isalnum())


def first_match(row, aliases, required=False, default=""):
    lookup = {norm(k): v for k, v in row.items()}
    for alias in aliases:
        key = norm(alias)
        if key in lookup and str(lookup[key]).strip() != "":
            return str(lookup[key]).strip()
    if required:
        raise KeyError(f"missing required column among aliases={aliases} in row={row}")
    return default


def read_csv(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def infer_case_from_h_over_r(h_over_r):
    mapping = {
        "4": "hR4",
        "2": "hR2",
        "1": "hR1",
        "0.5": "hR0p5",
        "0.35": "hR0p35",
    }
    return mapping.get(str(h_over_r).strip(), "")


def read_day7(path):
    rows = read_csv(path)
    out = {}
    duplicates = []

    for row in rows:
        case = first_match(row, ["case"], required=False, default="")
        h_over_r = first_match(row, ["h_over_R", "h/R", "hOverR"], required=False, default="")

        if not case:
            case = infer_case_from_h_over_r(h_over_r)
        if not case:
            raise ValueError(f"Day7 row에서 case를 식별할 수 없음: {row}")

        item = {
            "case": case,
            "h_over_R": h_over_r,
            "T_over_Tref": first_match(
                row,
                ["T_over_Tref", "T_Tref", "T/Tref", "thrust_ratio", "T_ratio", "TOverTref"],
                required=True,
            ),
            "P_over_Pref": first_match(
                row,
                ["P_over_Pref", "P_Pref", "P/Pref", "power_ratio", "P_ratio", "POverPref"],
                required=True,
            ),
            "day7_status": first_match(
                row,
                ["status", "day7_status", "qc_status"],
                required=False,
                default="ok",
            ),
        }

        if case in out:
            duplicates.append(case)
        out[case] = item

    return out, duplicates


def read_day9(path):
    rows = read_csv(path)
    out = {}
    duplicates = []

    for row in rows:
        case = first_match(row, ["case"], required=True)
        item = {
            "case": case,
            "h_over_R": first_match(row, ["h_over_R", "h/R", "hOverR"], required=True),
            "z_plane_m": first_match(row, ["z_plane_m", "zPlane", "z"], required=True),
            "rmax_m": first_match(row, ["rmax_m", "rmax"], required=True),
            "rmax_R": first_match(row, ["rmax_R", "rmax/R", "rmaxOverR"], required=True),
            "vr_peak_mps": first_match(
                row,
                ["vr_peak_mps", "vr_peak", "Vr_peak_mps", "VrPeak"],
                required=True,
            ),
            "n_points": first_match(row, ["n_points", "nPoints"], required=False, default=""),
            "valid_bins": first_match(row, ["valid_bins", "validBins"], required=False, default=""),
            "day9_status": first_match(row, ["status", "day9_status"], required=False, default=""),
            "day9_note": first_match(row, ["note", "day9_note"], required=False, default=""),
            "source_xy": first_match(row, ["source_xy", "xy_path"], required=False, default=""),
        }

        if case in out:
            duplicates.append(case)
        out[case] = item

    return out, duplicates


def safe_float(value):
    try:
        return float(str(value).strip())
    except Exception:
        return None


def build_final(day7_map, day9_map):
    final_rows = []
    missing_day7 = []
    missing_day9 = []

    for case in REQUIRED_CASES:
        d7 = day7_map.get(case)
        d9 = day9_map.get(case)

        if d7 is None:
            missing_day7.append(case)
            continue
        if d9 is None:
            missing_day9.append(case)
            continue

        final_rows.append(
            {
                "case": case,
                "h_over_R": d9["h_over_R"] if d9["h_over_R"] else d7["h_over_R"],
                "T_over_Tref": d7["T_over_Tref"],
                "P_over_Pref": d7["P_over_Pref"],
                "z_plane_m": d9["z_plane_m"],
                "rmax_m": d9["rmax_m"],
                "rmax_R": d9["rmax_R"],
                "vr_peak_mps": d9["vr_peak_mps"],
                "n_points": d9["n_points"],
                "valid_bins": d9["valid_bins"],
                "day7_status": d7["day7_status"],
                "day9_status": d9["day9_status"],
                "day9_note": d9["day9_note"],
                "source_xy": d9["source_xy"],
            }
        )

    return final_rows, missing_day7, missing_day9


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "case",
        "h_over_R",
        "T_over_Tref",
        "P_over_Pref",
        "z_plane_m",
        "rmax_m",
        "rmax_R",
        "vr_peak_mps",
        "n_points",
        "valid_bins",
        "day7_status",
        "day9_status",
        "day9_note",
        "source_xy",
    ]
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_qc(path, rows, dup7, dup9, missing7, missing9):
    z_values = sorted({str(r["z_plane_m"]) for r in rows if str(r["z_plane_m"]).strip() != ""})
    status9 = [str(r["day9_status"]).strip() for r in rows]
    all_day9_ok = all(s == "ok" for s in status9)

    monotonic_msg = "not_checked"
    vals = [safe_float(r["rmax_R"]) for r in rows]
    if all(v is not None for v in vals):
        nonincreasing = all(vals[i] >= vals[i + 1] - 1e-12 for i in range(len(vals) - 1))
        monotonic_msg = "nonincreasing_with_decreasing_hR" if nonincreasing else "not_monotonic"

    lines = [
        "Day10 QC Report",
        "================",
        "",
        f"row_count: {len(rows)}",
        f"required_cases: {', '.join(REQUIRED_CASES)}",
        f"missing_in_day7: {missing7 if missing7 else 'none'}",
        f"missing_in_day9: {missing9 if missing9 else 'none'}",
        f"duplicate_cases_day7: {dup7 if dup7 else 'none'}",
        f"duplicate_cases_day9: {dup9 if dup9 else 'none'}",
        f"unique_z_plane_m: {z_values if z_values else 'none'}",
        f"all_day9_status_ok: {all_day9_ok}",
        f"rmax_R_trend_check: {monotonic_msg}",
        "",
    ]

    for row in rows:
        lines.append(
            f"{row['case']}: "
            f"h/R={row['h_over_R']}, "
            f"T/Tref={row['T_over_Tref']}, "
            f"P/Pref={row['P_over_Pref']}, "
            f"rmax/R={row['rmax_R']}, "
            f"Vr_peak={row['vr_peak_mps']}, "
            f"z={row['z_plane_m']}, "
            f"day7_status={row['day7_status']}, "
            f"day9_status={row['day9_status']}"
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--day7", required=True)
    ap.add_argument("--day9", required=True)
    ap.add_argument("--out-csv", required=True)
    ap.add_argument("--out-qc", required=True)
    args = ap.parse_args()

    day7_map, dup7 = read_day7(args.day7)
    day9_map, dup9 = read_day9(args.day9)
    final_rows, missing7, missing9 = build_final(day7_map, day9_map)

    if missing7 or missing9:
        raise SystemExit(f"join 실패: missing7={missing7}, missing9={missing9}")

    write_csv(Path(args.out_csv), final_rows)
    write_qc(Path(args.out_qc), final_rows, dup7, dup9, missing7, missing9)

    print("DONE")
    print(f"out_csv={args.out_csv}")
    print(f"out_qc={args.out_qc}")


if __name__ == "__main__":
    main()
