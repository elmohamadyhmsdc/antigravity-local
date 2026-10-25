"""Identity-aware short-lived face tracks; no model or storage dependencies."""
from dataclasses import dataclass
import numpy as np


def unit(value):
    if value is None:
        return None
    value = np.asarray(value, np.float32).ravel()
    norm = np.linalg.norm(value)
    return value / norm if np.isfinite(value).all() and norm > 1e-8 else None


def assignment(cost):
    """Minimum-cost rectangular assignment (Hungarian), rows <= columns."""
    n, m = cost.shape
    u, v = np.zeros(n + 1), np.zeros(m + 1)
    p, way = np.zeros(m + 1, int), np.zeros(m + 1, int)
    for i in range(1, n + 1):
        p[0], j0 = i, 0
        minimum, used = np.full(m + 1, np.inf), np.zeros(m + 1, bool)
        while True:
            used[j0] = True
            i0, delta, j1 = p[j0], np.inf, 0
            for j in range(1, m + 1):
                if used[j]:
                    continue
                cur = cost[i0 - 1, j - 1] - u[i0] - v[j]
                if cur < minimum[j]:
                    minimum[j], way[j] = cur, j0
                if minimum[j] < delta:
                    delta, j1 = minimum[j], j
            for j in range(m + 1):
                if used[j]:
                    u[p[j]] += delta
                    v[j] -= delta
                else:
                    minimum[j] -= delta
            j0 = j1
            if p[j0] == 0:
                break
        while True:
            j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
            if j0 == 0:
                break
    return {int(p[j] - 1): j - 1 for j in range(1, m + 1) if p[j]}


def iou(a, b):
    size = np.maximum(0, np.minimum(a[2:], b[2:]) - np.maximum(a[:2], b[:2]))
    intersection = float(np.prod(size))
    union = float(np.prod(a[2:] - a[:2]) + np.prod(b[2:] - b[:2]) - intersection)
    return intersection / max(union, 1e-8)


@dataclass
class Track:
    kps: np.ndarray
    box: np.ndarray
    embedding: object
    seen: int
    velocity: np.ndarray


class FaceTracker:
    def __init__(self, ttl=12):
        self.ttl, self.clock, self.next_id = ttl, 0, 0
        self.tracks = {}

    def clear(self):
        # Never reuse ids: cached selector decisions must not survive a cut.
        self.tracks.clear()

    def update(self, faces, alpha=0.6, smooth=True):
        self.clock += 1
        self.tracks = {i: t for i, t in self.tracks.items() if self.clock - t.seen <= self.ttl}
        old = list(self.tracks.items())
        points, boxes, embeddings = [], [], []
        for face in faces:
            kps = getattr(face, "kps", None)
            kps = np.asarray(kps, np.float32) if kps is not None else None
            if kps is not None and (kps.shape != (5, 2) or not np.isfinite(kps).all()):
                kps = None
            points.append(kps)
            box = getattr(face, "bbox", None)
            boxes.append(np.asarray(box, np.float32)[:4] if box is not None else
                         (np.r_[kps.min(0), kps.max(0)] if kps is not None else np.zeros(4)))
            embeddings.append(unit(getattr(face, "embedding", None)))
        if not faces:
            return []
        costs = np.full((len(faces), len(old) + len(faces)), 1.5)
        for row, (kps, box, emb) in enumerate(zip(points, boxes, embeddings)):
            if kps is None:
                continue
            centre = kps.mean(0)
            scale = max(float(np.linalg.norm(kps[0] - kps[1])) * 2, 1)
            for col, (_, track) in enumerate(old):
                age = self.clock - track.seen
                predicted = track.kps.mean(0) + track.velocity * age
                distance = float(np.linalg.norm(centre - predicted)) / scale
                sim = float(emb @ track.embedding) if emb is not None and track.embedding is not None else None
                if sim is not None and sim < 0.35:
                    continue
                if distance > (4 if sim is not None and sim > 0.6 else 1.5):
                    continue
                overlap = iou(box, track.box)
                costs[row, col] = ((1 - sim) * 1.2 + min(distance, 2) * .2 + (1 - overlap) * .1
                                   if sim is not None else distance * .7 + (1 - overlap) * .3)
        matches, ids = assignment(costs), []
        for row, face in enumerate(faces):
            kps, box, emb = points[row], boxes[row], embeddings[row]
            col = matches[row]
            matched = col < len(old) and costs[row, col] < 1.5
            if matched:
                tid, prev = old[col]
            else:
                self.next_id += 1
                tid, prev = self.next_id, None
            ids.append(tid)
            if kps is None:
                continue
            velocity = np.zeros(2) if prev is None else (kps.mean(0) - prev.kps.mean(0)) / (self.clock - prev.seen)
            # Avoid blending coordinates over a reacquisition or large jump.
            if prev is not None and self.clock - prev.seen == 1 and costs[row, col] < .8 and smooth:
                kps = alpha * kps + (1 - alpha) * prev.kps
                face.kps = kps
            self.tracks[tid] = Track(kps.copy(), box.copy(), emb if emb is not None else
                                     (prev.embedding if prev else None), self.clock, velocity)
        return ids
