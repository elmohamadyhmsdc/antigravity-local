"""
Antigravity Local - Source identity builder

inswapper consumes ONLY the source face's identity embedding (see
insightface INSwapper.get -> source_face.normed_embedding). So the best
likeness comes from ONE robust identity vector built by averaging many good
source faces, not from picking a single source face per target.

This also removes the per-frame source switching that caused identity flicker
in video, and skips re-loading/re-detecting every source image at swap time.
"""

from typing import List, Optional

import numpy as np


class AveragedSource:
    """Minimal stand-in for an insightface Face that exposes only what
    INSwapper.get needs: a unit-norm 512-d ``normed_embedding``."""

    def __init__(self, normed_embedding: np.ndarray):
        self.normed_embedding = np.asarray(normed_embedding, dtype=np.float32)


def _unit(v: np.ndarray) -> Optional[np.ndarray]:
    v = np.asarray(v, dtype=np.float32).ravel()
    n = np.linalg.norm(v)
    if not np.isfinite(n) or n < 1e-8:
        return None
    return v / n


def select_identity_faces(faceset, top_k=None):
    """Quality, medoid/outlier and duplicate gates shared by every V3 source."""
    rows = []
    for face in getattr(faceset, "faces", []) if faceset is not None else []:
        vector = _unit(face.embedding)
        quality = float(getattr(face, "quality", 0) or 0)
        if vector is not None and vector.size == 512 and np.isfinite(quality) and quality >= 0:
            rows.append((face, vector, max(min(quality, 1), 1e-3) * (.5 if getattr(face, "generated", False) else 1)))
    if not rows:
        return [], dict(input=0, kept=0, rejected=0, consistency=0, pose_coverage={})
    total = len(rows)
    matrix = np.stack([v for _, v, _ in rows])
    similarities = matrix @ matrix.T
    # A medoid resists a minority of incorrectly grouped or synthetic faces.
    real_indices = [i for i, (face, _, _) in enumerate(rows) if not getattr(face, "generated", False)]
    pool = real_indices or list(range(len(rows)))
    anchor_index = max(pool, key=lambda i: float(np.median(similarities[i, pool])))
    anchor = matrix[anchor_index]
    sims = matrix @ anchor
    real_sims = sims[pool]
    median = float(np.median(real_sims))
    mad = float(np.median(np.abs(real_sims - median)))
    threshold = max(.4, median - max(3 * mad, .1))
    candidates = sorted((r for r, similarity in zip(rows, sims) if similarity >= threshold),
                        key=lambda r: (not getattr(r[0], "generated", False), r[2]), reverse=True)
    kept = []
    for row in candidates:
        if kept and max(float(row[1] @ old[1]) for old in kept) >= .95:
            continue
        kept.append(row)
        if top_k and len(kept) >= top_k:
            break
    if not kept:
        return [], dict(input=total, kept=0, rejected=total, consistency=0, pose_coverage={})
    real_weight = sum(q for face, _, q in kept if not getattr(face, "generated", False))
    generated_weight = sum(q for face, _, q in kept if getattr(face, "generated", False))
    if real_weight and generated_weight:
        factor = min(1, real_weight * .25 / generated_weight)
        kept = [(face, vector, q * (factor if getattr(face, "generated", False) else 1)) for face, vector, q in kept]
    mean = _unit(sum(vector * q for _, vector, q in kept))
    coverage = {}
    for face, _, _ in kept:
        yaw, pitch = (getattr(face, "pose", None) or (0, 0, 0))[:2]
        key = f"{int(round(yaw / 20))},{int(round(pitch / 20))}"
        coverage[key] = coverage.get(key, 0) + 1
    return kept, dict(input=total, kept=len(kept), rejected=total-len(kept),
                      consistency=float(np.mean([v @ mean for _, v, _ in kept])), pose_coverage=coverage)


def build_identity_embedding(faceset, top_k=None, quality_weighted=True):
    rows, _ = select_identity_faces(faceset, top_k)
    if not rows:
        return None
    return _unit(sum(v * (q if quality_weighted else 1) for _, v, q in rows))


def build_source_from_faceset(
    faceset,
    top_k: Optional[int] = None,
    quality_weighted: bool = True,
) -> Optional[AveragedSource]:
    """Convenience: return an AveragedSource ready to pass to INSwapper.get,
    or None if the faceset has no usable embeddings."""
    emb = build_identity_embedding(faceset, top_k=top_k, quality_weighted=quality_weighted)
    if emb is None:
        return None
    return AveragedSource(emb)
