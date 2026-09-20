"""
Identity grouping for the gallery: match faces to known people, cluster the
rest into new people, suggest duplicate people, and tie bodies to people.

Pure NumPy / scikit-learn / SciPy - no models, files or database - so it's
unit-testable on CPU (test_gallery.py). Face similarities are cosine
similarities of InsightFace buffalo_l (w600k_r50) embeddings. Thresholds were
tuned on the curated library with eval_grouping.py (2026-09-19): the old greedy
0.35 grouping split 3 real people into 17 groups; average-linkage + matching
against known people recovers them with no wrong merges.

Hard rule used everywhere: two faces (or two bodies) seen in the same photo or
video frame are never the same person.
"""

from collections import defaultdict
from dataclasses import dataclass, replace
from typing import Callable, Dict, Hashable, Iterable, List, Optional, Sequence, Tuple

import cv2
import numpy as np


# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class GroupingParams:
    match_auto: float = 0.40        # identity score to auto-assign a face to a known person
    match_margin: float = 0.10      # ...and its lead over the runner-up person
    suggest: float = 0.25           # identity score worth asking the user about
    cluster_distance: float = 0.70  # average-linkage cut (1 - mean cosine similarity)
    seed_quality: float = 0.45      # lower-quality faces may join groups but never start them
    min_group_size: int = 2         # smallest cluster shown as a group
    auto_create_size: int = 3       # clusters at least this big (and cohesive) become people
    auto_create_cohesion: float = 0.40
    merge_suggest: float = 0.40     # person-to-person score for "possibly the same person"
    merge_auto: float = 0.60        # new groups this alike are folded together without asking
    body_auto: float = 0.86         # outfit similarity to auto-link a faceless body (same video/photo)
    body_margin: float = 0.06
    body_suggest: float = 0.78


STRICTNESS: Dict[str, GroupingParams] = {
    "strict": GroupingParams(match_auto=0.48, match_margin=0.14, suggest=0.30, cluster_distance=0.64,
                             seed_quality=0.55, auto_create_size=4, auto_create_cohesion=0.45,
                             merge_suggest=0.45, merge_auto=0.65, body_auto=0.90, body_margin=0.08, body_suggest=0.82),
    "balanced": GroupingParams(),
    "loose": GroupingParams(match_auto=0.34, match_margin=0.07, suggest=0.22, cluster_distance=0.75,
                            seed_quality=0.40, auto_create_size=2, auto_create_cohesion=0.35,
                            merge_suggest=0.35, merge_auto=0.55, body_auto=0.82, body_margin=0.05, body_suggest=0.74),
}


def params_for(strictness: str) -> GroupingParams:
    return STRICTNESS.get(strictness, STRICTNESS["balanced"])


# ---------------------------------------------------------------------------
# Embeddings
# ---------------------------------------------------------------------------

def normalize_rows(x) -> np.ndarray:
    x = np.asarray(x, dtype=np.float32)
    if x.ndim == 1:
        n = float(np.linalg.norm(x))
        return x / n if n > 0 else x
    if x.size == 0:
        return x.reshape(0, x.shape[1] if x.ndim == 2 else 0)
    n = np.linalg.norm(x, axis=1, keepdims=True)
    n[n == 0] = 1.0
    return x / n


@dataclass
class PersonModel:
    pid: int
    proto: np.ndarray    # quality-weighted mean embedding (unit)
    members: np.ndarray  # member embeddings, best quality first (unit)
    count: int


def build_person_models(embeddings: np.ndarray, person_ids: Sequence[int], qualities: Sequence[float],
                        cap: int = 300) -> Dict[int, PersonModel]:
    """One model per person from their assigned faces."""
    e = normalize_rows(embeddings)
    q = np.clip(np.asarray(qualities, dtype=np.float32), 0.05, 1.0)
    by_pid: Dict[int, List[int]] = defaultdict(list)
    for i, pid in enumerate(person_ids):
        if pid is not None:
            by_pid[int(pid)].append(i)
    models = {}
    for pid, idx in by_pid.items():
        idx = np.asarray(idx)
        w = q[idx] ** 2
        proto = normalize_rows((e[idx] * w[:, None]).sum(0))
        order = idx[np.argsort(-q[idx])][:cap]
        models[pid] = PersonModel(pid, proto, e[order], len(idx))
    return models


def identity_scores(embeddings: np.ndarray, models: Dict[int, PersonModel], k: int = 3) -> Tuple[List[int], np.ndarray]:
    """(person ids, N x P score matrix). Score = mean of the similarity to the
    person's prototype and the mean of the top-k most similar member faces -
    the prototype is robust, the top-k part catches pose-specific matches
    (a profile face resembles that person's other profile faces)."""
    pids = sorted(models)
    e = normalize_rows(embeddings)
    if not pids or len(e) == 0:
        return pids, np.zeros((len(e), len(pids)), dtype=np.float32)
    s = np.zeros((len(e), len(pids)), dtype=np.float32)
    for j, pid in enumerate(pids):
        m = models[pid]
        proto_sim = e @ m.proto
        sims = e @ m.members.T
        kk = min(k, sims.shape[1])
        top = np.partition(sims, sims.shape[1] - kk, axis=1)[:, -kk:] if kk < sims.shape[1] else sims
        s[:, j] = 0.5 * proto_sim + 0.5 * top.mean(1)
    return pids, s


# ---------------------------------------------------------------------------
# Matching faces to known people
# ---------------------------------------------------------------------------

@dataclass
class Match:
    index: int                 # position in the input
    person_id: Optional[int]
    score: float
    margin: float
    decision: Optional[str]    # "auto", "suggest" or None


def _group_by_frame(frame_keys: Sequence[Optional[Hashable]]) -> List[List[int]]:
    groups: Dict[Hashable, List[int]] = defaultdict(list)
    singles = []
    for i, key in enumerate(frame_keys):
        if key is None:
            singles.append([i])
        else:
            groups[key].append(i)
    return list(groups.values()) + singles


def _assign_within_frames(s: np.ndarray, frame_keys) -> np.ndarray:
    """Column index per row (-1 = none) so no two rows from the same frame share a column."""
    from scipy.optimize import linear_sum_assignment
    choice = np.full(s.shape[0], -1, dtype=int)
    if s.shape[1] == 0:
        return choice
    for idx in _group_by_frame(frame_keys):
        if len(idx) == 1:
            i = idx[0]
            if s[i].max() > -1:
                choice[i] = int(s[i].argmax())
            continue
        sub = s[idx]
        rows, cols = linear_sum_assignment(-sub)
        for r, c in zip(rows, cols):
            if sub[r, c] > -1:
                choice[idx[r]] = int(c)
    return choice


def match_faces(embeddings: np.ndarray, models: Dict[int, PersonModel], params: GroupingParams,
                frame_keys: Optional[Sequence[Optional[Hashable]]] = None,
                rejected: Optional[Sequence[Iterable[int]]] = None) -> List[Match]:
    """Best known person for each face, honouring "not this person" feedback and
    the one-person-per-frame rule."""
    n = len(embeddings)
    pids, s = identity_scores(embeddings, models)
    if not pids:
        return [Match(i, None, 0.0, 0.0, None) for i in range(n)]
    col = {pid: j for j, pid in enumerate(pids)}
    if rejected:
        for i, rej in enumerate(rejected):
            for pid in rej or ():
                if pid in col:
                    s[i, col[pid]] = -2.0
    choice = _assign_within_frames(s, frame_keys if frame_keys is not None else [None] * n)
    out = []
    for i in range(n):
        j = choice[i]
        if j < 0:
            out.append(Match(i, None, 0.0, 0.0, None))
            continue
        score = float(s[i, j])
        others = np.delete(s[i], j)
        runner_up = float(others.max()) if len(others) else 0.0
        margin = score - max(runner_up, 0.0)
        if score >= params.match_auto and margin >= params.match_margin:
            decision = "auto"
        elif score >= params.suggest:
            decision = "suggest"
        else:
            decision = None
        out.append(Match(i, pids[j] if decision else None, score, margin, decision))
    return out


# ---------------------------------------------------------------------------
# Clustering faces nobody has named yet
# ---------------------------------------------------------------------------

@dataclass
class Cluster:
    indices: List[int]    # positions in the input
    cohesion: float       # mean pairwise similarity
    quality: float        # mean face quality


def _cannot_link_mask(frame_keys: Sequence[Optional[Hashable]]) -> np.ndarray:
    keys = list(frame_keys)
    n = len(keys)
    mask = np.zeros((n, n), dtype=bool)
    for idx in _group_by_frame(keys):
        if len(idx) > 1:
            ix = np.asarray(idx)
            mask[np.ix_(ix, ix)] = True
    np.fill_diagonal(mask, False)
    return mask


def _average_linkage(e: np.ndarray, frame_keys, distance: float) -> np.ndarray:
    from sklearn.cluster import AgglomerativeClustering
    if len(e) == 1:
        return np.zeros(1, dtype=int)
    d = np.clip(1.0 - e @ e.T, 0.0, 2.0).astype(np.float64)
    # Same-frame pairs get the maximum distance so average linkage keeps them apart
    d[_cannot_link_mask(frame_keys)] = 2.0
    np.fill_diagonal(d, 0.0)
    return AgglomerativeClustering(n_clusters=None, metric="precomputed", linkage="average",
                                   distance_threshold=distance).fit_predict(d)


def _leader_then_link(e: np.ndarray, q: np.ndarray, frame_keys, distance: float,
                      micro: float = 0.25) -> np.ndarray:
    """For big inboxes: fold near-identical faces into micro-clusters first, then
    average-link the micro-cluster centroids. Keeps memory O(N * leaders)."""
    order = np.argsort(-q)
    leaders: List[int] = []
    lead_vecs = np.zeros_like(e)
    owner = np.full(len(e), -1, dtype=int)
    for i in order:
        if leaders:
            sims = lead_vecs[:len(leaders)] @ e[i]
            j = int(sims.argmax())
            same_frame = frame_keys[i] is not None and frame_keys[i] == frame_keys[leaders[j]]
            if 1.0 - sims[j] <= micro and not same_frame:
                owner[i] = j
                continue
        owner[i] = len(leaders)
        lead_vecs[len(leaders)] = e[i]
        leaders.append(int(i))
    cents = normalize_rows(np.stack([e[owner == j].mean(0) for j in range(len(leaders))]))
    lead_labels = _average_linkage(cents, [None] * len(leaders), distance)
    return lead_labels[owner]


def cluster_faces(embeddings: np.ndarray, qualities: Sequence[float], params: GroupingParams,
                  frame_keys: Optional[Sequence[Optional[Hashable]]] = None,
                  direct_limit: int = 2500) -> List[Cluster]:
    """Groups of faces that look like one person, biggest first. Faces that fit
    no group are simply left out."""
    e = normalize_rows(embeddings)
    n = len(e)
    if n == 0:
        return []
    q = np.asarray(qualities, dtype=np.float32)
    keys = list(frame_keys) if frame_keys is not None else [None] * n

    seeds = np.where(q >= params.seed_quality)[0]
    labels = np.full(n, -1, dtype=int)
    if len(seeds) >= 2:
        seed_keys = [keys[i] for i in seeds]
        if len(seeds) <= direct_limit:
            seed_labels = _average_linkage(e[seeds], seed_keys, params.cluster_distance)
        else:
            seed_labels = _leader_then_link(e[seeds], q[seeds], seed_keys, params.cluster_distance)
        labels[seeds] = seed_labels
    elif len(seeds) == 1:
        labels[seeds] = 0

    # One face per frame per cluster: keep the member closest to the cluster centre
    for lab in set(labels[labels >= 0].tolist()):
        idx = np.where(labels == lab)[0]
        centre = normalize_rows(e[idx].mean(0))
        seen: Dict[Hashable, int] = {}
        for i in idx[np.argsort(-(e[idx] @ centre))]:
            key = keys[i]
            if key is None:
                continue
            if key in seen:
                labels[i] = -1
            else:
                seen[key] = i

    # Drop clusters that are too small to count as a group
    for lab in set(labels[labels >= 0].tolist()):
        if (labels == lab).sum() < params.min_group_size:
            labels[labels == lab] = -1

    # Let the leftovers (low quality, ejected, singletons) join a group they clearly belong to
    group_labels = sorted(set(labels[labels >= 0].tolist()))
    loose = np.where(labels < 0)[0]
    if group_labels and len(loose):
        models = build_person_models(e[labels >= 0], labels[labels >= 0].tolist(), q[labels >= 0])
        matches = match_faces(e[loose], models, params)
        for m in matches:
            if m.decision != "auto":
                continue
            i = loose[m.index]
            members = np.where(labels == m.person_id)[0]
            if keys[i] is not None and any(keys[j] == keys[i] for j in members):
                continue
            labels[i] = m.person_id

    labels = _merge_alike_groups(e, q, keys, labels, params.merge_auto)

    clusters = []
    for lab in set(labels[labels >= 0].tolist()):
        idx = np.where(labels == lab)[0]
        sims = e[idx] @ e[idx].T
        k = len(idx)
        cohesion = float((sims.sum() - k) / (k * (k - 1))) if k > 1 else 1.0
        clusters.append(Cluster(idx.tolist(), cohesion, float(q[idx].mean())))
    clusters.sort(key=lambda c: (-len(c.indices), -c.cohesion))
    return clusters


def _merge_alike_groups(e: np.ndarray, q: np.ndarray, keys, labels: np.ndarray, threshold: float) -> np.ndarray:
    """Average linkage stops early on pose-split groups of one person; fold
    groups whose person-pair score clears `threshold` (union-find, best pair
    first, never across a same-frame conflict)."""
    labs = sorted(set(labels[labels >= 0].tolist()))
    if len(labs) < 2:
        return labels
    models = build_person_models(e[labels >= 0], labels[labels >= 0].tolist(), q[labels >= 0])
    pairs = []
    for i, a in enumerate(labs):
        for b in labs[i + 1:]:
            sc = person_pair_score(models[a], models[b])
            if sc >= threshold:
                pairs.append((sc, a, b))
    parent = {lab: lab for lab in labs}
    frames = {lab: {keys[i] for i in np.where(labels == lab)[0] if keys[i] is not None} for lab in labs}

    def root(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for _, a, b in sorted(pairs, reverse=True):
        ra, rb = root(a), root(b)
        if ra == rb or frames[ra] & frames[rb]:
            continue
        parent[rb] = ra
        frames[ra] |= frames.pop(rb)
    out = labels.copy()
    for lab in labs:
        out[labels == lab] = root(lab)
    return out


def should_auto_create(cluster: Cluster, params: GroupingParams) -> bool:
    return len(cluster.indices) >= params.auto_create_size and cluster.cohesion >= params.auto_create_cohesion


# ---------------------------------------------------------------------------
# Duplicate people
# ---------------------------------------------------------------------------

def person_pair_score(a: PersonModel, b: PersonModel, top: int = 5) -> float:
    proto = float(a.proto @ b.proto)
    cross = a.members[:50] @ b.members[:50].T
    best = np.sort(cross.max(1))[::-1][:top]
    return 0.5 * proto + 0.5 * float(best.mean())


def suggest_merges(models: Dict[int, PersonModel], params: GroupingParams,
                   distinct: Optional[Iterable[Tuple[int, int]]] = None) -> List[Tuple[int, int, float]]:
    """(person a, person b, score) pairs that may be the same person, best first.
    Pairs the user already marked as different are skipped."""
    skip = {frozenset(p) for p in (distinct or ())}
    pids = sorted(models)
    if len(pids) < 2:
        return []
    protos = np.stack([models[p].proto for p in pids])
    quick = protos @ protos.T
    out = []
    for i in range(len(pids)):
        for j in range(i + 1, len(pids)):
            if quick[i, j] < params.merge_suggest - 0.15 or frozenset((pids[i], pids[j])) in skip:
                continue
            sc = person_pair_score(models[pids[i]], models[pids[j]])
            if sc >= params.merge_suggest:
                out.append((pids[i], pids[j], round(sc, 4)))
    out.sort(key=lambda t: -t[2])
    return out


# ---------------------------------------------------------------------------
# Faces <-> bodies within one image
# ---------------------------------------------------------------------------

HEAD_KPTS = (0, 1, 2, 3, 4)
KPT_VISIBLE = 0.3


def _inter(a, b) -> float:
    w = min(a[2], b[2]) - max(a[0], b[0])
    h = min(a[3], b[3]) - max(a[1], b[1])
    return max(0.0, w) * max(0.0, h)


def face_body_score(face_box, body_box, face_kps=None, body_kpts=None, body_kpt_scores=None) -> float:
    """0..1 plausibility that this face belongs to this body."""
    fx1, fy1, fx2, fy2 = [float(v) for v in face_box[:4]]
    bx1, by1, bx2, by2 = [float(v) for v in body_box[:4]]
    fw, fh = max(fx2 - fx1, 1.0), max(fy2 - fy1, 1.0)
    bw, bh = max(bx2 - bx1, 1.0), max(by2 - by1, 1.0)
    containment = _inter((fx1, fy1, fx2, fy2), (bx1, by1, bx2, by2)) / (fw * fh)
    if containment < 0.5:
        return 0.0
    rel_y = ((fy1 + fy2) / 2 - by1) / bh
    v = 1.0 if rel_y <= 0.35 else max(0.0, 1.0 - (rel_y - 0.35) / 0.25)
    ratio = fw / bw
    s = 1.0 if 0.1 <= ratio <= 0.85 else 0.5
    geo = containment * v * s
    if body_kpts is None or body_kpt_scores is None:
        return geo
    k = np.asarray(body_kpts, dtype=np.float32)
    ks = np.asarray(body_kpt_scores, dtype=np.float32)
    vis = [i for i in HEAD_KPTS if ks[i] >= KPT_VISIBLE]
    if not vis:
        return 0.6 * geo  # head keypoints not visible: weaker evidence
    pad_x, pad_y = 0.25 * fw, 0.25 * fh
    inside = np.mean([(fx1 - pad_x) <= k[i][0] <= (fx2 + pad_x) and (fy1 - pad_y) <= k[i][1] <= (fy2 + pad_y)
                      for i in vis])
    kp = float(inside)
    if face_kps is not None and ks[0] >= KPT_VISIBLE:
        nose_d = float(np.linalg.norm(np.asarray(face_kps, dtype=np.float32)[2] - k[0])) / fw
        kp = 0.5 * kp + 0.5 * max(0.0, 1.0 - nose_d / 0.5)
    return 0.4 * geo + 0.6 * kp


def associate_faces_bodies(face_boxes: Sequence, bodies: Sequence, face_kps: Optional[Sequence] = None,
                           min_score: float = 0.35) -> List[Tuple[int, int, float]]:
    """One-to-one (face index, body index, score) pairs. `bodies` items need
    .bbox and optionally .kpts / .kpt_scores (body_detector.Body)."""
    from scipy.optimize import linear_sum_assignment
    if not len(face_boxes) or not len(bodies):
        return []
    m = np.zeros((len(face_boxes), len(bodies)), dtype=np.float32)
    for i, fb in enumerate(face_boxes):
        fk = face_kps[i] if face_kps is not None else None
        for j, b in enumerate(bodies):
            m[i, j] = face_body_score(fb, b.bbox, fk, getattr(b, "kpts", None), getattr(b, "kpt_scores", None))
    rows, cols = linear_sum_assignment(-m)
    return [(int(r), int(c), float(m[r, c])) for r, c in zip(rows, cols) if m[r, c] >= min_score]


EXTENT_LABELS = {"full": "Full body", "knee": "Knee-up", "upper": "Upper body", "head": "Head & shoulders"}


def body_extent(kpt_scores) -> Optional[str]:
    if kpt_scores is None:
        return None
    ks = np.asarray(kpt_scores, dtype=np.float32)
    if max(ks[15], ks[16]) >= KPT_VISIBLE:
        return "full"
    if max(ks[13], ks[14]) >= KPT_VISIBLE:
        return "knee"
    if max(ks[11], ks[12]) >= KPT_VISIBLE or max(ks[7], ks[8]) >= KPT_VISIBLE:
        return "upper"
    return "head"


# ---------------------------------------------------------------------------
# Outfit descriptor (same clothes -> same person, within one video/photo)
# ---------------------------------------------------------------------------

_H_BINS, _S_EDGES, _V_EDGES = 12, (50, 120, 190, 256), (0, 64, 128, 192, 256)
REGION_LEN = _H_BINS * (len(_S_EDGES) - 1) + (len(_V_EDGES) - 1)   # 40
REGION_WEIGHTS = (0.6, 0.4)  # torso, legs


def _region_hist(hsv: np.ndarray) -> np.ndarray:
    if hsv.size == 0:
        return np.zeros(REGION_LEN, dtype=np.float32)
    h, s, v = hsv[..., 0].ravel(), hsv[..., 1].ravel(), hsv[..., 2].ravel()
    chroma = (s >= _S_EDGES[0]) & (v >= 40)
    h2, _, _ = np.histogram2d(h[chroma], s[chroma], bins=[_H_BINS, list(_S_EDGES)], range=[[0, 180], [0, 256]])
    vh, _ = np.histogram(v[~chroma], bins=list(_V_EDGES))
    hist = np.concatenate([h2.ravel(), vh]).astype(np.float32)
    total = hist.sum()
    if total < 20:  # too few pixels to say anything
        return np.zeros(REGION_LEN, dtype=np.float32)
    return np.sqrt(hist / total)  # Hellinger form: dot product = Bhattacharyya coefficient


def _kp_box(k, ks, idx, thr=KPT_VISIBLE):
    pts = [k[i] for i in idx if ks[i] >= thr]
    if len(pts) < 2:
        return None
    pts = np.asarray(pts)
    return pts[:, 0].min(), pts[:, 1].min(), pts[:, 0].max(), pts[:, 1].max()


def outfit_regions(bbox, kpts=None, kpt_scores=None):
    """(torso box, legs box) in image pixels; either may be None."""
    x1, y1, x2, y2 = [float(v) for v in bbox[:4]]
    w, h = x2 - x1, y2 - y1
    torso = legs = None
    if kpts is not None and kpt_scores is not None:
        k, ks = np.asarray(kpts), np.asarray(kpt_scores)
        tb = _kp_box(k, ks, (5, 6, 11, 12))
        if tb is not None and tb[3] - tb[1] > 4 and tb[2] - tb[0] > 4:
            tw = tb[2] - tb[0]
            torso = (tb[0] + 0.1 * tw, tb[1] + 0.1 * (tb[3] - tb[1]), tb[2] - 0.1 * tw, tb[3])
            lb = _kp_box(k, ks, (11, 12, 13, 14, 15, 16))
            if lb is not None and lb[3] - tb[3] > 8:
                legs = (lb[0] - 0.1 * tw, tb[3], lb[2] + 0.1 * tw, lb[3])
            return torso, legs
    torso = (x1 + 0.25 * w, y1 + 0.22 * h, x2 - 0.25 * w, y1 + 0.55 * h)
    legs = (x1 + 0.25 * w, y1 + 0.58 * h, x2 - 0.25 * w, y1 + 0.92 * h)
    return torso, legs


def appearance_descriptor(img_bgr: np.ndarray, bbox, kpts=None, kpt_scores=None) -> Optional[np.ndarray]:
    """80 floats: HSV histograms of the torso and legs regions (zeros where a
    region isn't visible). None if nothing usable is visible."""
    ih, iw = img_bgr.shape[:2]
    parts = []
    for box in outfit_regions(bbox, kpts, kpt_scores):
        if box is None:
            parts.append(np.zeros(REGION_LEN, dtype=np.float32))
            continue
        bx1, by1 = int(max(0, box[0])), int(max(0, box[1]))
        bx2, by2 = int(min(iw, box[2])), int(min(ih, box[3]))
        if bx2 - bx1 < 3 or by2 - by1 < 3:
            parts.append(np.zeros(REGION_LEN, dtype=np.float32))
            continue
        hsv = cv2.cvtColor(img_bgr[by1:by2, bx1:bx2], cv2.COLOR_BGR2HSV)
        parts.append(_region_hist(hsv))
    desc = np.concatenate(parts)
    return desc if desc.any() else None


def appearance_similarity(a, b) -> float:
    """Weighted Bhattacharyya coefficient over the regions both bodies show (0..1)."""
    if a is None or b is None:
        return 0.0
    a, b = np.asarray(a, dtype=np.float32), np.asarray(b, dtype=np.float32)
    total = weight = 0.0
    for r, wt in enumerate(REGION_WEIGHTS):
        ra, rb = a[r * REGION_LEN:(r + 1) * REGION_LEN], b[r * REGION_LEN:(r + 1) * REGION_LEN]
        if ra.any() and rb.any():
            total += wt * float(ra @ rb)
            weight += wt
    return total / weight if weight else 0.0


# ---------------------------------------------------------------------------
# Bodies without a usable face
# ---------------------------------------------------------------------------

@dataclass
class BodyLink:
    body_id: int
    person_id: int
    method: str          # "appearance" or "weak_face"
    confidence: float
    decision: str        # "auto" or "suggest"


def link_faceless_bodies(bodies: Sequence[Dict], anchor_person: Callable[[Dict], Optional[int]],
                         models: Dict[int, PersonModel], params: GroupingParams) -> List[BodyLink]:
    """Suggest/auto-link bodies whose own face wasn't usable.

    `bodies` are body records (dicts with id, media_id, frame_number, appearance,
    weak_face_embedding, rejected_person_ids). `anchor_person(body)` returns the
    person a body already belongs to through its face or a manual link, else None.
    Evidence, strongest first:
      1. a low-quality face on the body that still matches a known person clearly
      2. the same outfit as an identified body in the same photo/video
    """
    anchors_by_media: Dict[Hashable, List[Tuple[Dict, int]]] = defaultdict(list)
    loose = []
    for b in bodies:
        pid = anchor_person(b)
        if pid is not None:
            anchors_by_media[b.get("media_id")].append((b, pid))
        else:
            loose.append(b)

    proposals: List[BodyLink] = []
    for b in loose:
        rejected = set(b.get("rejected_person_ids") or ())
        best: Optional[BodyLink] = None
        wf = b.get("weak_face_embedding")
        if wf is not None and models:
            m = match_faces(np.asarray([wf], dtype=np.float32), models, params, rejected=[rejected])[0]
            if m.decision == "auto":
                best = BodyLink(b["id"], m.person_id, "weak_face", round(m.score, 4), "auto")
            elif m.decision == "suggest":
                best = BodyLink(b["id"], m.person_id, "weak_face", round(m.score, 4), "suggest")
        app = b.get("appearance")
        if app is not None and (best is None or best.decision != "auto"):
            per_person: Dict[int, float] = {}
            same_frame_people = set()
            for a, pid in anchors_by_media.get(b.get("media_id"), []):
                if a.get("frame_number") == b.get("frame_number"):
                    same_frame_people.add(pid)  # that person is already elsewhere in this frame
                    continue
                if pid in rejected:
                    continue
                sim = appearance_similarity(app, a.get("appearance"))
                per_person[pid] = max(per_person.get(pid, 0.0), sim)
            for pid in same_frame_people:
                per_person.pop(pid, None)
            if per_person:
                ranked = sorted(per_person.items(), key=lambda t: -t[1])
                pid, sim = ranked[0]
                runner = ranked[1][1] if len(ranked) > 1 else 0.0
                if sim >= params.body_auto and sim - runner >= params.body_margin:
                    best = BodyLink(b["id"], pid, "appearance", round(sim, 4), "auto")
                elif sim >= params.body_suggest and best is None:
                    best = BodyLink(b["id"], pid, "appearance", round(sim, 4), "suggest")
        if best is not None:
            proposals.append(best)

    # Two faceless bodies in one frame can't both be the same person: keep the stronger
    by_frame: Dict[Tuple, BodyLink] = {}
    frame_of = {b["id"]: (b.get("media_id"), b.get("frame_number")) for b in loose}
    kept = []
    for p in sorted(proposals, key=lambda p: (p.decision != "auto", -p.confidence)):
        key = (frame_of[p.body_id], p.person_id)
        if key in by_frame:
            continue
        by_frame[key] = p
        kept.append(p)
    return kept


def with_overrides(params: GroupingParams, **kw) -> GroupingParams:
    return replace(params, **kw)
