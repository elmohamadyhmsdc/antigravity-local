"""Drawn (anime, cartoon, manga) and other non-human faces, told apart by the face embedding.

The face detector fires on drawn faces and gives many of them a good quality score, but the
recogniser maps them all near one shared direction that real faces stay away from. Measured
2026-10-31 on 63 drawn faces from the phone's anime folders against 720 real faces (lora_datasets,
the DFL sample videos, insightface samples): every usable real face scored <= 0.13, only
blurred or covered ones reached 0.17; drawn faces scored 0.13-0.62 (95% >= 0.18, leave-one-out).
Non-faces (a dog, Groot, hair, fabric) also score high; photoreal renders and statues do not.
DRAWN_MIN_SCORE keeps a margin above every real face, so a few very realistic drawings pass.

Keep DIRECTION_B64 and DRAWN_MIN_SCORE identical to mobile/lib/domain/scan/drawn_faces.dart
(test_drawn_faces.py checks it).
"""
import base64

import numpy as np

# Unit mean of the drawn faces' normed embeddings, 512 x float32 little-endian.
DIRECTION_B64 = (
    "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"
)
DRAWN_MIN_SCORE = 0.20

_direction = np.frombuffer(base64.b64decode(DIRECTION_B64), dtype="<f4").astype(np.float64)


def drawn_score(embedding) -> float:
    """Cosine between a face embedding (any length scale) and the drawn-face direction."""
    v = np.asarray(embedding, dtype=np.float64).ravel()
    norm = float(np.linalg.norm(v))
    if v.shape != (512,) or not np.isfinite(norm) or norm == 0:
        return 0.0
    return float(v @ _direction / norm)


def is_drawn(embedding) -> bool:
    """True for a drawn or non-human face: never a person."""
    return embedding is not None and drawn_score(embedding) >= DRAWN_MIN_SCORE
