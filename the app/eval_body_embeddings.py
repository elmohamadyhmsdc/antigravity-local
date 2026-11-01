"""
Phase 8 gate (roadmap section 9): do the exposed-region embeddings follow IDENTITY on YOUR library? Read-only.

Ground truth = bodies of people identified through a FACE (or by hand) that also carry a chest / buttocks
embedding. Export a backup without a password (unzipped folder or .agbackup) and run:

    venv\\Scripts\\python eval_body_embeddings.py <library> [--eps 0.15,0.2,0.25,0.3]

Reports per half (chest / buttocks):
  * same-person vs different-person cosine similarity, and pairwise precision at every threshold
  * the same, only for pairs taken in DIFFERENT photos days apart (the case that matters: generic embeddings tend
    to follow lighting / pose / crop / event instead of the person)
  * DBSCAN clusters at each eps: pairwise precision (do two bodies in one cluster belong to one person?)
Verdict: the persistent clusters and one-tap assignment ship ONLY at pairwise precision >= 0.95 (cross-event
precision included). Below that the phone keeps the ranked "similar photos" search and the cluster feature stays
OFF (`body_clusters_enabled`). OSNet `reid` is added only if it improves the Phase 0 LLR over the outfit cue.
Writes eval/body_embeddings_<time>.json.
"""

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

from eval_body_links import blob, load_tables

HERE = Path(__file__).resolve().parent
TARGET = 0.95
DAY_MS = 24 * 3600 * 1000
THRESHOLDS = [round(0.5 + 0.05 * i, 2) for i in range(10)]


def load_bodies(tables, column):
    media = {m["id"]: m for m in tables["media"]}
    out = []
    for b in tables["bodies"]:
        if b.get("kind", "person") != "person" or b.get("person_id") is None:
            continue
        if b.get("face_id") is None and b.get("link_method") != "manual":
            continue
        raw = blob(b.get(column))
        if raw is None or len(raw) != 384 * 4:
            continue
        m = media.get(b.get("media_id"), {})
        out.append({"id": b["id"], "person": b["person_id"], "media": b.get("media_id"),
                    "taken": m.get("taken_at"), "vec": np.frombuffer(raw, dtype="<f4").astype(np.float32)})
    return out


def pair_stats(bodies, cross_event_only=False):
    if len(bodies) < 2:
        return None
    mat = np.stack([b["vec"] for b in bodies])
    mat /= np.maximum(np.linalg.norm(mat, axis=1, keepdims=True), 1e-9)
    sims = mat @ mat.T
    rows = []
    for i in range(len(bodies)):
        for j in range(i + 1, len(bodies)):
            a, b = bodies[i], bodies[j]
            if a["media"] == b["media"]:
                continue
            if cross_event_only and (a["taken"] is None or b["taken"] is None or abs(a["taken"] - b["taken"]) < DAY_MS):
                continue
            rows.append((float(sims[i, j]), a["person"] == b["person"]))
    if not rows:
        return None
    table = {}
    for t in THRESHOLDS:
        kept = [same for s, same in rows if s >= t]
        table[str(t)] = {"pairs": len(kept), "precision": round(sum(kept) / len(kept), 4) if kept else None}
    return {"pairs": len(rows), "same_person_pairs": sum(1 for _, y in rows if y),
            "same_mean": round(float(np.mean([s for s, y in rows if y])), 4) if any(y for _, y in rows) else None,
            "different_mean": round(float(np.mean([s for s, y in rows if not y])), 4) if any(not y for _, y in rows) else None,
            "precision_by_threshold": table}


def cluster_precision(bodies, eps, min_points=2):
    """Pairwise precision of DBSCAN clusters (cosine distance), same algorithm as the phone's `dbscan`."""
    vecs = [b["vec"] / max(float(np.linalg.norm(b["vec"])), 1e-9) for b in bodies]
    n = len(vecs)
    label = [-2] * n

    def near(i):
        return [j for j in range(n) if 1 - float(vecs[i] @ vecs[j]) <= eps]

    cluster = 0
    for i in range(n):
        if label[i] != -2:
            continue
        seeds = near(i)
        if len(seeds) < min_points:
            label[i] = -1
            continue
        label[i] = cluster
        queue = list(seeds)
        k = 0
        while k < len(queue):
            j = queue[k]
            k += 1
            if label[j] == -1:
                label[j] = cluster
            if label[j] != -2:
                continue
            label[j] = cluster
            more = near(j)
            if len(more) >= min_points:
                queue.extend(more)
        cluster += 1
    pairs = same = 0
    for c in range(cluster):
        members = [bodies[i] for i in range(n) if label[i] == c]
        for a in range(len(members)):
            for b in range(a + 1, len(members)):
                if members[a]["media"] == members[b]["media"]:
                    continue
                pairs += 1
                same += members[a]["person"] == members[b]["person"]
    return {"eps": eps, "clusters": cluster, "clustered": sum(1 for x in label if x >= 0), "noise": sum(1 for x in label if x < 0),
            "pairs": pairs, "pairwise_precision": round(same / pairs, 4) if pairs else None}


def evaluate(tables, eps_values):
    report = {"target_pairwise_precision": TARGET, "halves": {}}
    for name, column in (("chest", "chest_embedding"), ("buttocks", "buttocks_embedding")):
        bodies = load_bodies(tables, column)
        half = {"bodies": len(bodies), "people": len({b["person"] for b in bodies})}
        if len(bodies) < 20 or half["people"] < 2:
            half["verdict"] = "not enough identified bodies with embeddings (need >= 20 bodies of >= 2 people)"
        else:
            half["all_pairs"] = pair_stats(bodies)
            half["cross_event_pairs"] = pair_stats(bodies, cross_event_only=True)
            half["clusters"] = [cluster_precision(bodies, e) for e in eps_values]
            best = [c for c in half["clusters"] if c["pairwise_precision"] is not None and c["pairwise_precision"] >= TARGET and c["pairs"] >= 20]
            cross = half["cross_event_pairs"]
            cross_ok = cross is not None and any((r["precision"] or 0) >= TARGET and r["pairs"] >= 20
                                                 for r in cross["precision_by_threshold"].values())
            half["verdict"] = (f"clusters may ship at eps {max(c['eps'] for c in best)} (cross-event precision "
                               f"{'ok' if cross_ok else 'NOT proven: keep one-tap assignment off'})") if best else \
                "below 0.95: ship the ranked 'similar photos' search only; clusters stay OFF"
        report["halves"][name] = half
    return report


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("library")
    ap.add_argument("--eps", default="0.15,0.2,0.25,0.3")
    args = ap.parse_args(argv)
    report = evaluate(load_tables(args.library), [float(e) for e in args.eps.split(",")])
    out = HERE / "eval"
    out.mkdir(exist_ok=True)
    target = out / time.strftime("body_embeddings_%Y%m%d_%H%M%S.json")
    target.write_text(json.dumps(report, indent=1), encoding="utf-8")
    for name, half in report["halves"].items():
        print(f"{name}: {half['bodies']} bodies / {half['people']} people -> {half['verdict']}")
    print("wrote", target)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
