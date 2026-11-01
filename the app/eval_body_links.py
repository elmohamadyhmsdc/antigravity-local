"""
Phase 0 (roadmap section 9): calibrate the body-link thresholds on YOUR curated library. Read-only.

The library lives on the phone. Export a backup WITHOUT encryption (Backup screen -> turn the password off, or
unzip a decrypted copy) and run:

    venv\\Scripts\\python eval_body_links.py <library.agbackup | folder with db/*.jsonl> [--windows 1,3,6,12,24]

Ground truth = bodies of people that were identified through a FACE (or by hand): two such bodies are the same
person or not. For every pair of different photos it measures the outfit similarity, whether the photos are
within the event window, and answers:
  * how precise is "same outfit" at each threshold, inside / outside the window  -> event_auto / event_suggest
  * the log-likelihood-ratio table per similarity bin (capped), for the fusion of roadmap section 7.3
  * how much the shoulder/torso ratio varies inside one person vs between people  -> bone_ratio_veto spread
Targets: precision >= 0.98 for auto, >= 0.85 for suggest. Writes eval/body_links_<time>.json; never copies images.
"""

import argparse
import base64
import json
import math
import random
import sys
import time
import zipfile
from collections import defaultdict
from pathlib import Path

import numpy as np

import person_linking as pl

HERE = Path(__file__).resolve().parent
HOUR = 3600 * 1000
THRESHOLDS = [round(0.70 + 0.02 * i, 2) for i in range(16)]    # 0.70 .. 1.00
MAX_PAIRS = 400_000


def load_tables(path):
    """table -> list of row dicts, from an unencrypted .agbackup (zip) or an unzipped folder."""
    path = Path(path)
    tables = defaultdict(list)

    def add(name, text):
        table = name.split("/")[-1].split(".")[0]
        for line in text.splitlines():
            if line.strip():
                tables[table].append(json.loads(line))

    if path.is_dir():
        for f in sorted(path.rglob("*.jsonl")):
            add(f.name, f.read_text(encoding="utf-8"))
    else:
        if not zipfile.is_zipfile(path):
            raise SystemExit("Not a zip: an encrypted backup must be exported without a password first.")
        with zipfile.ZipFile(path) as z:
            for name in sorted(z.namelist()):
                if name.startswith("db/") and name.endswith(".jsonl"):
                    add(name, z.read(name).decode("utf-8"))
    return tables


def blob(value):
    return base64.b64decode(value["$b64"]) if isinstance(value, dict) and "$b64" in value else None


def anchored_bodies(tables, skin_share=0.55):
    """Bodies identified through a face or by hand, with outfit, time and keypoint ratio."""
    media = {m["id"]: m for m in tables["media"]}
    out, skipped_skin = [], 0
    for b in tables["bodies"]:
        if b.get("kind", "person") != "person" or b.get("person_id") is None:
            continue
        if b.get("face_id") is None and b.get("link_method") != "manual":
            continue
        raw = blob(b.get("appearance"))
        if raw is None or len(raw) != 320:
            continue
        app = np.frombuffer(raw, dtype="<f4").astype(np.float32)
        if pl.skin_dominated(app, skin_share):
            skipped_skin += 1
            continue
        m = media.get(b.get("media_id"), {})
        out.append({"id": b["id"], "person": b["person_id"], "media": b.get("media_id"), "app": app,
                    "taken": m.get("taken_at"), "ratio": frontal_ratio(b, m)})
    return out, skipped_skin


def frontal_ratio(body, media):
    """shoulder width / torso length for a frontal, upright, full-length body, else None (pixels: kpts are
    normalised by width and height separately)."""
    w, h = media.get("width"), media.get("height")
    if not body.get("kpts") or not w or not h or body.get("extent") != "full":
        return None
    try:
        k = np.asarray(json.loads(body["kpts"]), dtype=np.float64)
    except ValueError:
        return None
    if k.shape != (17, 3):
        return None
    pts, scores = k[:, :2] * [w, h], k[:, 2]
    if any(scores[i] < pl.KPT_VISIBLE for i in (5, 6, 11, 12, 15, 16)):
        return None
    sh, hp = (pts[5] + pts[6]) / 2, (pts[11] + pts[12]) / 2
    torso, width = float(np.linalg.norm(hp - sh)), float(np.linalg.norm(pts[5] - pts[6]))
    if torso < 1 or abs(hp[0] - sh[0]) / max(abs(hp[1] - sh[1]), 1e-6) > 0.47 or width < 0.6 * torso:
        return None
    return width / torso


def pairs(bodies, seed=0):
    """(similarity, same_person, hours_apart or None) over pairs from different photos."""
    rng = random.Random(seed)
    idx = [(i, j) for i in range(len(bodies)) for j in range(i + 1, len(bodies))]
    if len(idx) > MAX_PAIRS:
        idx = rng.sample(idx, MAX_PAIRS)
    matrix = np.asarray([b["app"] for b in bodies], dtype=np.float32)
    out = []
    for i, j in idx:
        a, b = bodies[i], bodies[j]
        if a["media"] == b["media"]:
            continue
        sim = float(pl.appearance_similarity_many(a["app"], matrix[j:j + 1])[0])
        gap = None if a["taken"] is None or b["taken"] is None else abs(a["taken"] - b["taken"]) / HOUR
        out.append((sim, a["person"] == b["person"], gap))
    return out


def precision_table(rows):
    table = {}
    for t in THRESHOLDS:
        kept = [same for sim, same, _ in rows if sim >= t]
        table[str(t)] = {"pairs": len(kept), "precision": round(sum(kept) / len(kept), 4) if kept else None}
    return table


def pick(table, target, minimum=30):
    for t in THRESHOLDS:
        row = table[str(t)]
        if row["pairs"] >= minimum and row["precision"] is not None and row["precision"] >= target:
            return t
    return None


def llr_table(rows, cap=4.0, bin_width=0.02):
    same = [s for s, y, _ in rows if y]
    diff = [s for s, y, _ in rows if not y]
    edges = np.arange(0.5, 1.0001, bin_width)
    hs, _ = np.histogram(same, bins=edges)
    hd, _ = np.histogram(diff, bins=edges)
    ps, pd = (hs + 1) / (hs.sum() + len(hs)), (hd + 1) / (hd.sum() + len(hd))
    return [{"from": round(float(edges[i]), 2), "same": int(hs[i]), "different": int(hd[i]),
             "llr": round(float(max(-cap, min(cap, math.log(ps[i] / pd[i])))), 3)} for i in range(len(hs))]


def bone_spread(bodies):
    by_person = defaultdict(list)
    for b in bodies:
        if b["ratio"] is not None:
            by_person[b["person"]].append(b["ratio"])
    within = [abs(r1 - r2) / max(r1, r2) for rs in by_person.values() for i, r1 in enumerate(rs) for r2 in rs[i + 1:]]
    people = [np.mean(rs) for rs in by_person.values() if rs]
    between = [abs(a - b) / max(a, b) for i, a in enumerate(people) for b in people[i + 1:]]
    if len(within) < 20 or len(between) < 3:
        return {"verdict": "not enough frontal full-length bodies", "within": len(within), "between": len(between)}
    p95 = float(np.percentile(within, 95))
    med = float(np.median(between))
    return {"within_p95": round(p95, 3), "between_median": round(med, 3),
            "verdict": f"use spread {round(p95 * 1.2, 2)}" if med > p95 * 1.2 else "ratios do not separate people: keep the veto off"}


def evaluate(tables, windows):
    bodies, skipped_skin = anchored_bodies(tables)
    people = {b["person"] for b in bodies}
    report = {"bodies": len(bodies), "people": len(people), "skin_dominated_skipped": skipped_skin}
    if len(people) < 2:
        report["error"] = "need at least two identified people with outfits"
        return report
    rows = pairs(bodies)
    report["pairs"] = len(rows)
    report["all_pairs"] = precision_table(rows)
    report["windows"] = {}
    for w in windows:
        inside = [r for r in rows if r[2] is not None and r[2] <= w]
        table = precision_table(inside)
        report["windows"][str(w)] = {"pairs": len(inside), "same_person": sum(1 for r in inside if r[1]),
                                     "precision": table, "event_auto": pick(table, 0.98),
                                     "event_suggest": pick(table, 0.85)}
    report["outside_6h"] = precision_table([r for r in rows if r[2] is None or r[2] > 6])
    report["llr_within_6h"] = llr_table([r for r in rows if r[2] is not None and r[2] <= 6])
    report["bone_ratio"] = bone_spread(bodies)
    return report


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("library")
    ap.add_argument("--windows", default="1,3,6,12,24")
    args = ap.parse_args(argv)
    report = evaluate(load_tables(args.library), [float(w) for w in args.windows.split(",")])
    out = HERE / "eval"
    out.mkdir(exist_ok=True)
    target = out / time.strftime("body_links_%Y%m%d_%H%M%S.json")
    target.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in ("all_pairs", "outside_6h", "llr_within_6h")}, indent=1))
    print(f"\nwrote {target}\nSet event_auto / event_suggest / event_window_ms in person_linking.GroupingParams "
          "from the window you want, then regenerate the fixtures.")
    return 0 if "error" not in report else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
