"""Reference identity selection shared by the video swap engines."""
from typing import Sequence

import numpy as np


SELECT_MIN_SIMILARITY = 0.35
SELECT_RECHECK_FRAMES = 12  # Compatibility: identities are now checked every frame.


def match_reference(embedding, references, selected, min_similarity=SELECT_MIN_SIMILARITY):
    if embedding is None or references is None or len(references) == 0:
        return False
    embedding = np.asarray(embedding, np.float32).ravel()
    norm = np.linalg.norm(embedding)
    if not np.isfinite(norm) or norm < 1e-8:
        return False
    scores = references @ (embedding / norm)
    best = int(np.argmax(scores))
    if best not in selected or float(scores[best]) < min_similarity:
        return False
    # Several references can be poses of the same selected person. Agreement
    # between selected poses is useful evidence, not identity ambiguity.
    others = [float(score) for index, score in enumerate(scores) if index not in selected]
    return not others or float(scores[best]) - max(others) >= .05


class FaceSelector:
    """Verify current pixels against all references, including unselected people."""

    def __init__(self, reference_embeddings: Sequence, selected_indices: Sequence[int]):
        refs = np.asarray(reference_embeddings, np.float32).reshape(len(reference_embeddings), -1)
        if refs.shape[1] != 512 or not np.isfinite(refs).all():
            raise ValueError("Invalid reference identity vectors")
        norms = np.linalg.norm(refs, axis=1, keepdims=True)
        if np.any(norms < 1e-8) or not selected_indices or any(i < 0 or i >= len(refs) for i in selected_indices):
            raise ValueError("Invalid reference selection")
        self.references = refs / np.maximum(norms, 1e-8)
        self.selected = {int(i) for i in selected_indices}

    def reset(self):
        pass

    def wants(self, track_id, frame_no, embed):
        return match_reference(embed(), self.references, self.selected)
