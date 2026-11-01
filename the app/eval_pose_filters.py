"""
Phase 0, pose half (roadmap section 9): are the Tier-A pose rules right on YOUR photos? Read-only.

The library lives on the phone. Export a backup without a password, unzip it, and run:

    venv\\Scripts\\python eval_pose_filters.py <unzipped backup folder> [--per-tag 30] [--seed 0]
        -> eval\\pose_<time>\\sheet.html: ~30 random bodies per rule with the rule's verdict; mark correct / wrong
           (the sheet points at the backup's own crops with file:// links; nothing is copied) and press Download
        -> the same sheet ends with nearest-neighbour rows for the pose descriptor (one exemplar + its 8 closest)
    venv\\Scripts\\python eval_pose_filters.py --score labels.json
        -> precision per rule; a rule below 0.85 moves from tier A (filter) to tier B (suggestion)

The rules and the descriptor are pose_filters.py, held identical to the phone's Dart code by the golden cases.
"""

import argparse
import json
import random
import sys
import time
from collections import defaultdict
from pathlib import Path

import numpy as np

import pose_filters as pf
from eval_body_links import load_tables

HERE = Path(__file__).resolve().parent
EVAL = HERE / "eval"
TARGET = 0.85


def bodies_with_poses(tables):
    media = {m["id"]: m for m in tables["media"]}
    yaw = {f["id"]: f.get("yaw") for f in tables.get("faces", [])}
    out = []
    for b in tables["bodies"]:
        if b.get("kind", "person") != "person" or not b.get("kpts"):
            continue
        m = media.get(b.get("media_id"), {})
        pose = pf.Pose.from_normalised(b["kpts"], m.get("width"), m.get("height"), b.get("extent"),
                                       yaw.get(b.get("face_id")))
        if pose is not None:
            out.append({"id": b["id"], "crop": b.get("crop_path"), "pose": pose})
    return out


def sample_by_tag(items, per_tag, seed):
    rng = random.Random(seed)
    by_tag = defaultdict(list)
    for it in items:
        for tag in pf.tier_a_tags(it["pose"]):
            by_tag[tag].append(it)
    return {tag: rng.sample(v, min(per_tag, len(v))) for tag, v in sorted(by_tag.items())}, {t: len(v) for t, v in by_tag.items()}


def neighbours(items, rows=8, k=8, seed=0):
    feats = [(it, pf.build_feature(it["pose"])) for it in items]
    feats = [(it, f) for it, f in feats if f is not None]
    rng = random.Random(seed)
    out = []
    for it, f in rng.sample(feats, min(rows, len(feats))):
        ranked = []
        for other, g in feats:
            if other["id"] == it["id"]:
                continue
            r = pf.compare(f, g)
            if r:
                ranked.append((r[0] * r[1], r[0], other))
        ranked.sort(key=lambda x: -x[0])
        out.append((it, [(round(s, 3), o) for _, s, o in ranked[:k]]))
    return out


def sheet(folder, samples, nn):
    def img(it):
        return f'<img src="file:///{(Path(folder) / "crops" / (it["crop"] or "")).as_posix()}" height="150">'
    parts = []
    for tag, items in samples.items():
        parts.append(f"<h3>{tag}</h3>")
        for it in items:
            parts.append(f'<span class="c" data-tag="{tag}" data-id="{it["id"]}">{img(it)}<br>'
                         f'<label><input type="radio" name="{tag}_{it["id"]}" value="correct">ok</label> '
                         f'<label><input type="radio" name="{tag}_{it["id"]}" value="wrong">no</label></span>')
    parts.append("<h3>Descriptor neighbours (exemplar first, then the closest poses with their score)</h3>")
    for it, near in nn:
        parts.append("<div>" + img(it) + " &rarr; " + "".join(f'{img(o)}<small>{s}</small> ' for s, o in near) + "</div>")
    return ("<!doctype html><meta charset=utf-8><title>Pose rules</title><style>body{font:14px system-ui;background:#111;color:#eee}"
            ".c{display:inline-block;margin:4px;text-align:center}</style><button onclick=save()>Download labels.json</button>"
            + "".join(parts) + """<script>
function save(){const out={};document.querySelectorAll('.c').forEach(c=>{const t=c.dataset.tag,id=c.dataset.id,
 v=c.querySelector('input:checked');(out[t]=out[t]||[]).push({id:+id,verdict:v?v.value:null});});
const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify({tags:out},null,1)],{type:'application/json'}));
a.download='labels.json';a.click();}</script>""")


def score(labels):
    report = {}
    for tag, rows in labels["tags"].items():
        done = [r for r in rows if r["verdict"] in ("correct", "wrong")]
        ok = sum(r["verdict"] == "correct" for r in done)
        precision = ok / len(done) if done else None
        report[tag] = {"labelled": len(done), "correct": ok,
                       "precision": None if precision is None else round(precision, 3),
                       "tier": "A" if precision is not None and precision >= TARGET and len(done) >= 15 else "B (or too few labels)"}
    return report


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", nargs="?")
    ap.add_argument("--per-tag", type=int, default=30)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--score", metavar="LABELS_JSON")
    args = ap.parse_args(argv)
    EVAL.mkdir(exist_ok=True)
    if args.score:
        report = score(json.loads(Path(args.score).read_text(encoding="utf-8")))
        for tag, r in report.items():
            print(f"{tag:15s} labelled {r['labelled']:3d} precision {r['precision']}  -> tier {r['tier']}")
        (EVAL / "pose_precision.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
        return 0
    if not args.folder:
        ap.error("give the unzipped backup folder (or --score labels.json)")
    items = bodies_with_poses(load_tables(args.folder))
    samples, totals = sample_by_tag(items, args.per_tag, args.seed)
    out = EVAL / time.strftime("pose_%Y%m%d_%H%M%S")
    out.mkdir()
    (out / "sheet.html").write_text(sheet(args.folder, samples, neighbours(items, seed=args.seed)), encoding="utf-8")
    (out / "report.json").write_text(json.dumps({"bodies": len(items), "per_tag_total": totals}, indent=1), encoding="utf-8")
    print(json.dumps({"bodies": len(items), "per_tag_total": totals}, indent=1))
    print("sheet:", out / "sheet.html")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
