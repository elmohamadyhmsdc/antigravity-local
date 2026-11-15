"""
Replay the PHONE's grouping on a labelled face set and count what the user would see.

    venv\\Scripts\\python eval_grouping_sim.py <faces.npz> [--photos 100] [--galleries 30] [--strictness auto]

<faces.npz> comes from eval_grouping_extract.py (e.g. LFW). Each simulated gallery mixes a few people seen
often (family), some seen a few times and some seen once, shuffled into scan order. The replay mirrors
mobile/lib/domain/grouping: an `apply [match, cluster]` round every 100 new faces while scanning (incremental),
then the full run - round 1, the provisional-people merge round, and `review` - and the quick-review question
count of review_questions.dart (actionable questions only; the local doubt audit is not replayed).

Reported per gallery size (mean over galleries):
  people     people created           ideal = identities seen at least twice
  extra      people beyond one per identity (duplicates - what the user saw as "Person 9, 12, 27...")
  wrong      faces sitting on a person whose majority is someone else
  sorted     share of faces of repeat identities that ended up on a person
  questions  open quick-review questions
CPU only, no database, no files written.
"""

import argparse
import sys
from collections import Counter, defaultdict

import numpy as np

import grouping_core as gc
import person_linking as pl

INCREMENTAL_EVERY = 100   # groupEveryNewFaces
MEMBER_CAP = 100          # groupingMemberCap
BATCH = 24                # reviewBatchSize


def make_gallery(data, rng, photos: int):
    """Photo ids of one simulated gallery: ~45% of photos from 3-6 frequent people, ~35% from people seen 2-5
    times, the rest from people seen once."""
    label, photo, centre = data["label"], data["photo"], data["centre"]
    by_person = defaultdict(set)
    for lab, ph, c in zip(label, photo, centre):
        if c:
            by_person[int(lab)].add(int(ph))
    rich = [p for p, s in by_person.items() if len(s) >= 15]
    mid = [p for p, s in by_person.items() if 3 <= len(s) < 15]
    any_ = [p for p, s in by_person.items() if len(s) >= 1]
    chosen = []
    used = set()
    budget = int(photos * 0.45)
    for p in rng.choice(rich, size=int(rng.integers(3, 7)), replace=False):
        take = sorted(by_person[p])
        rng.shuffle(take)
        k = min(len(take), max(4, budget // 4 + int(rng.integers(-3, 4))))
        chosen += take[:k]
        used.add(p)
    while len(chosen) < int(photos * 0.8):
        p = int(rng.choice(mid))
        if p in used:
            continue
        take = sorted(by_person[p])
        rng.shuffle(take)
        chosen += take[:int(rng.integers(2, 6))]
        used.add(p)
    while len(chosen) < photos:
        p = int(rng.choice(any_))
        if p in used:
            continue
        chosen.append(int(rng.choice(sorted(by_person[p]))))
        used.add(p)
    chosen = chosen[:photos]
    rng.shuffle(chosen)
    return chosen


class Phone:
    """The phone's database, reduced to what grouping touches."""

    def __init__(self, emb, qual, frame, strictness, merge_people):
        self.emb, self.qual, self.frame = emb, qual, frame
        self.person = {}            # face index -> person id
        self.named = set()          # people the user named (never auto-merged)
        self.next_pid = 1
        self.strictness = strictness
        self.merge_people = merge_people

    def snapshot(self, faces):
        by_pid = defaultdict(list)
        for f, p in self.person.items():
            by_pid[p].append(f)
        models = {}
        for p, fs in by_pid.items():
            fs = np.asarray(fs)
            models.update(pl.build_person_models(self.emb[fs], [p] * len(fs), self.qual[fs], cap=MEMBER_CAP))
        pending = [gc.PendingFace(int(f), self.emb[f], float(self.qual[f]), self.frame[f])
                   for f in faces if f not in self.person]
        frames = defaultdict(set)
        for f, p in self.person.items():
            frames[self.frame[f]].add(p)
        distinct = set()
        for ps in frames.values():
            ps = sorted(ps)
            for i, a in enumerate(ps):
                for b in ps[i + 1:]:
                    distinct.add((a, b))
        provisional = sorted(set(by_pid) - self.named)
        return gc.Snapshot(models, pending, [], sorted(distinct), set(), link_alike_people=True,
                           provisional_person_ids=provisional)

    def apply(self, plan):
        for a in plan.assignments:
            if a.decision == "auto" and a.face_id not in self.person:
                # one person per frame
                if any(self.person.get(o) == a.person_id for o in self.frames[self.frame[a.face_id]]):
                    continue
                self.person[a.face_id] = a.person_id
        for g in plan.groups:
            if not g.auto_create or any(f in self.person for f in g.face_ids):
                continue
            pid = self.next_pid
            self.next_pid += 1
            for f in g.face_ids:
                self.person[f] = pid
        for m in plan.merges or []:
            src, dst = m.absorb, m.into
            if src in self.named:
                continue
            fs_src = {self.frame[f] for f, p in self.person.items() if p == src}
            fs_dst = {self.frame[f] for f, p in self.person.items() if p == dst}
            if fs_src & fs_dst:
                continue
            for f, p in list(self.person.items()):
                if p == src:
                    self.person[f] = dst

    def run(self, faces, full: bool):
        self.frames = defaultdict(list)
        for f in faces:
            self.frames[self.frame[f]].append(f)
        stages = ["match", "cluster"]
        plan = gc.plan(self.snapshot(faces), "apply", stages, self.strictness)
        self.apply(plan)
        if not full:
            return None
        if self.merge_people:
            plan = gc.plan(self.snapshot(faces), "apply", ["people"], self.strictness)
            self.apply(plan)
            # fresh models can claim more faces after a merge
            self.apply(gc.plan(self.snapshot(faces), "apply", stages, self.strictness))
        return gc.plan(self.snapshot(faces), "review", ["match", "cluster", "duplicates"], self.strictness)


def count_questions(review, qual) -> int:
    """review_questions.buildQuestions, actionable only."""
    n = 0
    n += sum(1 for d in review.duplicates if d.score >= 0.47)
    n += sum(1 for g in review.groups if g.cohesion >= 0.45)
    per_person = defaultdict(lambda: Counter())
    for a in review.assignments:
        if a.decision != "suggest":
            continue
        if a.score < 0.32 or a.margin < 0.05 or qual[a.face_id] < 0.45:
            continue
        per_person[a.person_id]["high" if a.score >= 0.40 else "mid"] += 1
    for c in per_person.values():
        for k in c.values():
            n += -(-k // BATCH)
    return n


def score(phone, faces, label):
    lab = {f: int(label[f]) for f in faces}
    seen = Counter(lab[f] for f in faces if lab[f] >= 0)
    repeat = {l for l, c in seen.items() if c >= 2}
    by_pid = defaultdict(list)
    for f, p in phone.person.items():
        by_pid[p].append(lab[f])
    wrong = 0
    owners = defaultdict(set)
    for p, ls in by_pid.items():
        top, k = Counter(ls).most_common(1)[0]
        wrong += len(ls) - k
        owners[top].add(p)
    extra = sum(len(ps) - 1 for ps in owners.values())
    rep_faces = [f for f in faces if lab[f] in repeat]
    sorted_share = sum(1 for f in rep_faces if f in phone.person) / max(1, len(rep_faces))
    return dict(people=len(by_pid), ideal=len(repeat), extra=extra, wrong=wrong, sorted=sorted_share)


def simulate(data, photos, galleries, strictness, merge_people, seed=0):
    emb = pl.normalize_rows(data["embedding"])
    qual, label, photo = data["quality"], data["label"], data["photo"]
    faces_of = defaultdict(list)
    for i, ph in enumerate(photo):
        if data["face_px"][i] >= 40:
            faces_of[int(ph)].append(i)
    frame = {i: f"p{int(ph)}" for i, ph in enumerate(photo)}
    rng = np.random.default_rng(seed)
    rows = []
    for _ in range(galleries):
        order = make_gallery(data, rng, photos)
        phone = Phone(emb, qual, frame, strictness, merge_people)
        scanned, since = [], 0
        for ph in order:
            new = faces_of.get(ph, [])
            scanned += new
            since += len(new)
            if since >= INCREMENTAL_EVERY:
                phone.run(scanned, full=False)
                since = 0
        review = phone.run(scanned, full=True)
        r = score(phone, scanned, label)
        r["questions"] = count_questions(review, qual)
        r["faces"] = len(scanned)
        rows.append(r)
    return {k: float(np.mean([r[k] for r in rows])) for k in rows[0]}


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("npz")
    ap.add_argument("--photos", type=int, nargs="+", default=[100, 400])
    ap.add_argument("--galleries", type=int, default=20)
    ap.add_argument("--strictness", nargs="+", default=["balanced", "auto"])
    args = ap.parse_args(argv)
    data = dict(np.load(args.npz))
    print(f"{len(data['embedding'])} faces, {int((data['label'] >= 0).sum())} labelled\n")
    print(f"{'setup':<26}{'photos':>7}{'faces':>7}{'people':>8}{'ideal':>7}{'extra':>7}{'wrong':>7}"
          f"{'sorted':>8}{'questions':>10}")
    for photos in args.photos:
        for s in args.strictness:
            for merge in ([False] if s != "auto" else [True]):
                r = simulate(data, photos, args.galleries, s, merge)
                name = f"{s}{' +merge' if merge else ''}"
                print(f"{name:<26}{photos:>7}{r['faces']:>7.0f}{r['people']:>8.1f}{r['ideal']:>7.1f}"
                      f"{r['extra']:>7.1f}{r['wrong']:>7.1f}{r['sorted']:>8.0%}{r['questions']:>10.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
