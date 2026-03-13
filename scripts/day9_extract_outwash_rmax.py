#!/usr/bin/env python3
import argparse
import csv
import json
import math
from pathlib import Path


def read_raw_xy(xy_path):
    rows = []
    with open(xy_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            parts = s.split()
            vals = []
            ok = True
            for p in parts:
                try:
                    vals.append(float(p))
                except ValueError:
                    ok = False
                    break
            if ok:
                rows.append(vals)

    if not rows:
        raise RuntimeError(f"no numeric rows in {xy_path}")

    ncols = max(len(r) for r in rows)
    if ncols < 6:
        raise RuntimeError(
            f"need at least 6 numeric columns (x y z Ux Uy Uz). got max {ncols}"
        )

    clean = [r for r in rows if len(r) >= 6]
    if not clean:
        raise RuntimeError("no usable rows with >= 6 columns")

    return clean


def build_profile(rows, x0, y0, radius, z_plane, nbins, min_count):
    samples = []
    abs_vr_sum = 0.0

    for row in rows:
        x, y, z = row[0], row[1], row[2]
        ux, uy, uz = row[-3], row[-2], row[-1]

        dx = x - x0
        dy = y - y0
        rr = math.hypot(dx, dy)

        if rr <= 1e-14:
            continue

        erx = dx / rr
        ery = dy / rr
        vr = ux * erx + uy * ery

        samples.append((rr, vr, x, y, z))
        abs_vr_sum += abs(vr)

    if not samples:
        return {
            "status": "fail_no_radial_points",
            "note": "r=0 제외 후 남은 점이 없음",
            "profile": [],
            "peak": None,
            "n_points": 0,
            "valid_bins": 0,
            "z_plane_m": z_plane,
            "R_m": radius,
        }

    if abs_vr_sum <= 1e-12:
        return {
            "status": "fail_all_zero",
            "note": "Vr가 사실상 전부 0. plane 높이/축 원점 확인 필요",
            "profile": [],
            "peak": None,
            "n_points": len(samples),
            "valid_bins": 0,
            "z_plane_m": z_plane,
            "R_m": radius,
        }

    rmax_data = max(s[0] for s in samples)
    if rmax_data <= 0.0:
        return {
            "status": "fail_bad_radius_extent",
            "note": "최대 반경이 0 이하",
            "profile": [],
            "peak": None,
            "n_points": len(samples),
            "valid_bins": 0,
            "z_plane_m": z_plane,
            "R_m": radius,
        }

    dr = rmax_data / nbins
    bins = []
    for i in range(nbins):
        bins.append(
            {
                "i": i,
                "r_lo": i * dr,
                "r_hi": (i + 1) * dr,
                "r_center": (i + 0.5) * dr,
                "sum_vr": 0.0,
                "count": 0,
            }
        )

    for rr, vr, *_ in samples:
        idx = min(int(rr / dr), nbins - 1)
        bins[idx]["sum_vr"] += vr
        bins[idx]["count"] += 1

    profile = []
    positive_bins = []
    valid_bins = 0

    for b in bins:
        if b["count"] >= min_count:
            vr_mean = b["sum_vr"] / b["count"]
            valid_bins += 1
        else:
            vr_mean = None

        row = {
            "bin_id": b["i"],
            "r_lo_m": b["r_lo"],
            "r_hi_m": b["r_hi"],
            "r_center_m": b["r_center"],
            "r_center_R": b["r_center"] / radius,
            "vr_mean_mps": vr_mean,
            "count": b["count"],
        }
        profile.append(row)

        if vr_mean is not None and vr_mean > 0.0:
            positive_bins.append(row)

    if not positive_bins:
        return {
            "status": "fail_no_positive_outwash",
            "note": "양(+)의 annulus-mean Vr가 없음. z_plane 또는 축 중심 확인 필요",
            "profile": profile,
            "peak": None,
            "n_points": len(samples),
            "valid_bins": valid_bins,
            "z_plane_m": z_plane,
            "R_m": radius,
        }

    peak = max(positive_bins, key=lambda d: d["vr_mean_mps"])

    status = "ok"
    note_parts = []

    if peak["bin_id"] == 0 or peak["bin_id"] == nbins - 1:
        status = "warn_edge_peak"
        note_parts.append("peak가 첫/끝 bin에 걸림: plane 범위 또는 샘플 부족 가능성")

    if valid_bins < max(10, nbins // 10):
        if status == "ok":
            status = "warn_sparse_bins"
        note_parts.append("유효 bin 수가 적음")

    note = "; ".join(note_parts) if note_parts else "ok"

    return {
        "status": status,
        "note": note,
        "profile": profile,
        "peak": {
            "rmax_m": peak["r_center_m"],
            "rmax_R": peak["r_center_R"],
            "vr_peak_mps": peak["vr_mean_mps"],
            "peak_bin_id": peak["bin_id"],
        },
        "n_points": len(samples),
        "valid_bins": valid_bins,
        "z_plane_m": z_plane,
        "R_m": radius,
    }


def write_profile_csv(path, profile):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "bin_id",
                "r_lo_m",
                "r_hi_m",
                "r_center_m",
                "r_center_R",
                "vr_mean_mps",
                "count",
            ],
        )
        writer.writeheader()
        for row in profile:
            writer.writerow(row)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--xy", required=True, help="raw surface .xy file path")
    ap.add_argument("--x0", type=float, default=0.0)
    ap.add_argument("--y0", type=float, default=0.0)
    ap.add_argument("--R", type=float, required=True)
    ap.add_argument("--z-plane", type=float, required=True)
    ap.add_argument("--nbins", type=int, default=120)
    ap.add_argument("--min-count", type=int, default=1)
    ap.add_argument("--out-prefix", required=True)
    args = ap.parse_args()

    xy_path = Path(args.xy)
    out_prefix = Path(args.out_prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)

    rows = read_raw_xy(xy_path)
    result = build_profile(
        rows=rows,
        x0=args.x0,
        y0=args.y0,
        radius=args.R,
        z_plane=args.z_plane,
        nbins=args.nbins,
        min_count=args.min_count,
    )

    result["xy_path"] = str(xy_path.resolve())

    profile_csv = str(out_prefix) + "_profile.csv"
    summary_json = str(out_prefix) + "_summary.json"

    write_profile_csv(profile_csv, result["profile"])

    with open(summary_json, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    peak = result.get("peak")
    if peak is None:
        print(
            json.dumps(
                {
                    "status": result["status"],
                    "note": result["note"],
                    "n_points": result["n_points"],
                    "valid_bins": result["valid_bins"],
                    "z_plane_m": result["z_plane_m"],
                    "xy_path": result["xy_path"],
                },
                ensure_ascii=False,
            )
        )
    else:
        print(
            json.dumps(
                {
                    "status": result["status"],
                    "note": result["note"],
                    "n_points": result["n_points"],
                    "valid_bins": result["valid_bins"],
                    "z_plane_m": result["z_plane_m"],
                    "rmax_m": peak["rmax_m"],
                    "rmax_R": peak["rmax_R"],
                    "vr_peak_mps": peak["vr_peak_mps"],
                    "xy_path": result["xy_path"],
                },
                ensure_ascii=False,
            )
        )


if __name__ == "__main__":
    main()
