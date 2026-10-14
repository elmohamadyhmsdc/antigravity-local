"""
How many member faces per person must the phone send to POST /v1/grouping/plan?

Read-only: loads data/faces.json (your curated library) and never writes. Uses the same folds and
metrics as eval_grouping.py, but builds the person models with different member caps and compares
each cap with the PC's own setting (300, person_linking.build_person_models' default).

    venv\\Scripts\\python eval_member_cap.py [data_dir]        # default: data

Where the cap matters
  * face -> person matching scores a face as 0.5 * (similarity to the person's prototype) + 0.5 * (mean
    of its 3 most similar member faces). The prototype always uses ALL faces (the phone computes it),
    so only the "3 most similar members" part sees the cap: members are sent best-quality first, so a
    cap drops the lowest-quality faces. This is what is measured below.
  * duplicate-person scoring reads members[:50] only (person_linking.person_pair_score), so any cap >= 50
    gives identical duplicate suggestions - the script verifies that too.
  * clustering of unassigned faces needs no person models from the phone at all.

The phone's cap is `groupingMemberCap` in mobile/lib/domain/grouping/grouping_config.dart. A cap
"keeps accuracy" here when, against cap 300: no more wrong auto-matches, no more auto-matches of a hidden
person's faces, at least as many same-person duplicate pairs caught, no more false duplicate pairs, and
at least 99.5% of the faces get the same decision for the same person.
"""

import base64
import gzip
import sys
from collections import Counter

import numpy as np

from eval_grouping import load
from person_linking import STRICTNESS, build_person_models, match_faces, person_pair_score

CAPS = (300, 200, 150, 100, 75, 50)
BASELINE = 300
AGREEMENT_NEEDED = 0.995


def b64(vec):
    return base64.b64encode(np.asarray(vec, dtype="<f4").tobytes()).decode("ascii")


def measure(e, y, q, folds, people, params, cap, rng_seed=0):
    """Everything eval_grouping measures about matching + duplicates, for one cap."""
    decisions = {}
    auto = wrong = suggest = 0
    for k in range(5):
        tr, te = folds != k, folds == k
        models = build_person_models(e[tr], y[tr].tolist(), q[tr], cap=cap)
        idx = np.where(te)[0]
        for i, m, truth in zip(idx, match_faces(e[te], models, params), y[te]):
            decisions[int(i)] = (m.decision, m.person_id)
            if m.decision == "auto":
                auto += 1
                wrong += m.person_id != truth
            elif m.decision == "suggest":
                suggest += 1
    unknown_auto = unknown_n = 0
    for hidden in people:
        keep = y != hidden
        models = build_person_models(e[keep], y[keep].tolist(), q[keep], cap=cap)
        ms = match_faces(e[~keep], models, params)
        unknown_auto += sum(m.decision == "auto" for m in ms)
        unknown_n += len(ms)

    rng = np.random.default_rng(rng_seed)
    frags = []
    for pid in people:
        idx = rng.permutation(np.where(y == pid)[0])
        for part in np.array_split(idx, 3):
            if len(part):
                frags.append((pid, build_person_models(e[part], [pid] * len(part), q[part], cap=cap)[pid]))
    same, diff = [], []
    for i in range(len(frags)):
        for j in range(i + 1, len(frags)):
            s = person_pair_score(frags[i][1], frags[j][1])
            (same if frags[i][0] == frags[j][0] else diff).append(s)
    return {"auto": auto, "wrong": int(wrong), "suggest": suggest, "unknown_auto": unknown_auto,
            "unknown_n": unknown_n, "same_scores": same, "diff_scores": diff, "decisions": decisions}


def payload_mb(e, y, q, cap):
    """What the models part of one request weighs for this library: raw and gzipped base64 members."""
    raw = 0
    text = []
    for pid in sorted(set(y.tolist())):
        idx = np.where(y == pid)[0]
        order = idx[np.argsort(-q[idx])][:cap]
        raw += len(order) * 2048
        text.extend(b64(v) for v in e[order])
    return raw / 1e6, len(gzip.compress("".join(text).encode("ascii"), 5)) / 1e6


def main(argv):
    data_dir = argv[0] if argv else "data"
    try:
        faces, e, y, q = load(data_dir)
    except FileNotFoundError:
        print(f"No {data_dir}/faces.json - this benchmark needs a curated library (people with faces assigned).\n"
              "Pass the folder that holds one: venv\\Scripts\\python eval_member_cap.py <data_dir>")
        return 1
    people = sorted(set(y.tolist()))
    counts = Counter(y.tolist())
    print(f"{len(faces)} curated faces, people: {dict(counts)}\n")
    if len(people) < 2:
        print("Need at least 2 curated people to evaluate.")
        return 1
    biggest = max(counts.values())
    if biggest <= min(CAPS):
        print(f"Nobody has more than {biggest} faces, so every cap >= {min(CAPS)} sends everyone's faces: "
              "the cap is irrelevant for this library. Keep the default.")
        return 0

    rng = np.random.default_rng(0)
    folds = np.zeros(len(y), dtype=int)
    for pid in people:  # the same fold assignment as eval_grouping.py
        idx = np.where(y == pid)[0]
        folds[rng.permutation(idx)] = np.arange(len(idx)) % 5

    verdicts = {}
    for name, params in STRICTNESS.items():
        results = {cap: measure(e, y, q, folds, people, params, cap) for cap in CAPS}
        base = results[BASELINE]
        print(f"[{name}]   (person_linking.STRICTNESS['{name}'])")
        print(f"  {'cap':>5} {'auto':>6} {'wrong':>6} {'suggest':>8} {'unknown-auto':>13} {'dups caught':>12} "
              f"{'false dups':>11} {'same decision':>14} {'payload (raw / gzip)':>22}")
        for cap in CAPS:
            r = results[cap]
            same_decision = sum(r["decisions"][i] == base["decisions"][i] for i in base["decisions"]) / max(len(base["decisions"]), 1)
            caught = sum(s >= params.merge_suggest for s in r["same_scores"])
            false = sum(s >= params.merge_suggest for s in r["diff_scores"])
            raw, gz = payload_mb(e, y, q, cap)
            print(f"  {cap:>5} {r['auto']:>6} {r['wrong']:>6} {r['suggest']:>8} {r['unknown_auto']:>13} "
                  f"{caught:>6}/{len(r['same_scores']):<5} {false:>5}/{len(r['diff_scores']):<5} "
                  f"{same_decision:>13.1%} {raw:>10.1f} / {gz:.1f} MB")
            base_caught = sum(s >= params.merge_suggest for s in base["same_scores"])
            base_false = sum(s >= params.merge_suggest for s in base["diff_scores"])
            ok = (r["wrong"] <= base["wrong"] and r["unknown_auto"] <= base["unknown_auto"]
                  and caught >= base_caught and false <= base_false and same_decision >= AGREEMENT_NEEDED)
            verdicts.setdefault(cap, []).append(ok)
        dup_same = all(results[c]["same_scores"] == base["same_scores"] and results[c]["diff_scores"] == base["diff_scores"]
                       for c in CAPS if c >= 50)
        print(f"  duplicate scores identical for every cap >= 50: {'yes' if dup_same else 'NO'}\n")

    passing = [cap for cap in CAPS if all(verdicts[cap])]
    smallest = min(passing) if passing else BASELINE
    print("Caps that keep accuracy in every strictness preset: " + (", ".join(map(str, sorted(passing))) or "none"))
    print(f"-> smallest: {smallest}.  Set groupingMemberCap = {smallest} in "
          "mobile/lib/domain/grouping/grouping_config.dart (the app ships with 100).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
