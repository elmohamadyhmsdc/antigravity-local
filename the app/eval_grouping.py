"""
Measure gallery grouping accuracy against the people you've already curated.
Read-only: loads data/faces.json and never writes.

    venv\\Scripts\\python eval_grouping.py

Reports, per strictness preset (person_linking.STRICTNESS):
  - matching: 5-fold - train people models on 80% of each person's faces,
    match the other 20%. auto = assigned without asking; wrong = auto-assigned
    to the wrong person.
  - unknown person: hide one person entirely; their faces must NOT be
    auto-assigned to someone else.
  - clustering: pretend every curated face is unassigned and regroup them;
    pairwise precision / recall against your labels.
  - duplicate people: split each person into fragments, check which fragment
    pairs would be suggested as "same person".
"""

import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np

from person_linking import (STRICTNESS, build_person_models, cluster_faces, match_faces,
                            normalize_rows, person_pair_score)


def load(data_dir="data"):
    items = json.load(open(Path(data_dir) / "faces.json", encoding="utf-8"))["items"].values()
    faces = [f for f in items if f.get("person_id") is not None and f.get("embedding")]
    e = normalize_rows(np.array([f["embedding"] for f in faces], dtype=np.float32))
    y = np.array([int(f["person_id"]) for f in faces])
    q = np.array([float(f.get("quality_score") or 0.5) for f in faces], dtype=np.float32)
    return faces, e, y, q


def pairwise(labels, y):
    iu = np.triu_indices(len(y), 1)
    same = (y[:, None] == y[None, :])[iu]
    lab = np.asarray(labels)
    together = ((lab[:, None] == lab[None, :]) & (lab[:, None] >= 0))[iu]
    tp = (together & same).sum()
    return tp / max(together.sum(), 1), tp / max(same.sum(), 1)


def main():
    faces, e, y, q = load()
    people = sorted(set(y.tolist()))
    print(f"{len(faces)} curated faces, people: {dict(Counter(y.tolist()))}\n")
    if len(people) < 2:
        print("Need at least 2 curated people to evaluate.")
        return 1
    rng = np.random.default_rng(0)
    folds = np.zeros(len(y), dtype=int)
    for pid in people:
        idx = np.where(y == pid)[0]
        folds[rng.permutation(idx)] = np.arange(len(idx)) % 5

    for name, params in STRICTNESS.items():
        auto = wrong = sugg = 0
        for k in range(5):
            tr, te = folds != k, folds == k
            models = build_person_models(e[tr], y[tr].tolist(), q[tr])
            for m, truth in zip(match_faces(e[te], models, params), y[te]):
                if m.decision == "auto":
                    auto += 1
                    wrong += m.person_id != truth
                elif m.decision == "suggest":
                    sugg += 1
        unk_auto = unk_n = 0
        for hidden in people:
            keep = y != hidden
            models = build_person_models(e[keep], y[keep].tolist(), q[keep])
            ms = match_faces(e[~keep], models, params)
            unk_auto += sum(m.decision == "auto" for m in ms)
            unk_n += len(ms)
        clusters = cluster_faces(e, q, params)
        labels = np.full(len(y), -1)
        for ci, c in enumerate(clusters):
            labels[c.indices] = ci
        prec, rec = pairwise(labels, y)
        created = sum(len(c.indices) >= params.auto_create_size and c.cohesion >= params.auto_create_cohesion
                      for c in clusters)
        print(f"[{name}]")
        print(f"  matching      auto {auto}/{len(y)} ({auto / len(y):.0%})  wrong {wrong}  suggest {sugg}")
        print(f"  unknown       auto-assigned {unk_auto}/{unk_n} faces of a hidden person (should be 0)")
        print(f"  clustering    {len(clusters)} groups for {len(people)} people, {created} auto-created, "
              f"precision {prec:.3f} recall {rec:.3f}, ungrouped {int((labels < 0).sum())}")

        # fragments of the same person vs different people
        same_scores, diff_scores = [], []
        frags = []
        for pid in people:
            idx = rng.permutation(np.where(y == pid)[0])
            for part in np.array_split(idx, 3):
                if len(part):
                    frags.append((pid, build_person_models(e[part], [pid] * len(part), q[part])[pid]))
        for i in range(len(frags)):
            for j in range(i + 1, len(frags)):
                sc = person_pair_score(frags[i][1], frags[j][1])
                (same_scores if frags[i][0] == frags[j][0] else diff_scores).append(sc)
        caught = sum(s >= params.merge_suggest for s in same_scores)
        false = sum(s >= params.merge_suggest for s in diff_scores)
        print(f"  duplicates    same-person pairs flagged {caught}/{len(same_scores)} "
              f"(min {min(same_scores):.2f}), different-person pairs flagged {false}/{len(diff_scores)} "
              f"(max {max(diff_scores):.2f})\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
