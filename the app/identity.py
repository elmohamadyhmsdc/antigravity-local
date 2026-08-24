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


def build_identity_embedding(
    faceset,
    top_k: Optional[int] = None,
    quality_weighted: bool = True,
) -> Optional[np.ndarray]:
    """Build one unit-norm identity embedding from a Faceset.

    Args:
        faceset: a reface_engine.Faceset (FaceData has .embedding and .quality)
        top_k: if set, keep only the highest-quality K faces before averaging
        quality_weighted: weight each face by its quality score when averaging

    Returns:
        unit-norm 512-d float32 vector, or None if no usable faces.
    """
    if faceset is None or not getattr(faceset, "faces", None):
        return None

    items = []  # (unit_embedding, quality)
    for fd in faceset.faces:
        u = _unit(fd.embedding)
        if u is None:
            continue
        q = float(getattr(fd, "quality", 0.0) or 0.0)
        items.append((u, q))

    if not items:
        return None

    # Keep the best faces if requested
    if top_k and top_k > 0 and len(items) > top_k:
        items.sort(key=lambda t: t[1], reverse=True)
        items = items[:top_k]

    embeds = np.stack([u for u, _ in items], axis=0)  # (N, 512)

    if quality_weighted and any(q > 0 for _, q in items):
        w = np.array([max(q, 1e-3) for _, q in items], dtype=np.float32)
        w = w / w.sum()
        mean = (embeds * w[:, None]).sum(axis=0)
    else:
        mean = embeds.mean(axis=0)

    return _unit(mean)


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
