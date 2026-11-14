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
    """Verify current pixels against all references, including unselected people, with temporal evidence."""

    def __init__(self, reference_embeddings: Sequence, selected_indices: Sequence[int],
                 adaptive_recognition: bool = True):
        refs = np.asarray(reference_embeddings, np.float32).reshape(len(reference_embeddings), -1)
        if refs.shape[1] != 512 or not np.isfinite(refs).all():
            raise ValueError("Invalid reference identity vectors")
        norms = np.linalg.norm(refs, axis=1, keepdims=True)
        if np.any(norms < 1e-8) or not selected_indices or any(i < 0 or i >= len(refs) for i in selected_indices):
            raise ValueError("Invalid reference selection")
        self.references = refs / np.maximum(norms, 1e-8)
        self.selected = {int(i) for i in selected_indices}
        self.adaptive_recognition = bool(adaptive_recognition)
        self.track_history = {}
        self.track_confirmed_counts = {}

    def reset(self):
        self.track_history.clear()
        self.track_confirmed_counts.clear()

    def can_skip_recognition(self, track_id, frame_no, det_score: float = 1.0, motion_jump: bool = False) -> bool:
        if not getattr(self, "adaptive_recognition", True) or track_id is None or track_id <= 0:
            return False
        confirmed = self.track_confirmed_counts.get(track_id, 0)
        hist = self.track_history.get(track_id, [])
        return (confirmed >= 3 and hist and float(np.mean(hist)) >= 0.40
                and det_score >= 0.65 and not motion_jump and (frame_no % 4 != 0))

    def wants(self, track_id, frame_no, embed):
        emb = embed()
        if emb is None:
            return False
        emb = np.asarray(emb, np.float32).ravel()
        norm = np.linalg.norm(emb)
        if not np.isfinite(norm) or norm < 1e-8:
            return False
        scores = self.references @ (emb / norm)
        best = int(np.argmax(scores))
        best_score = float(scores[best])
        others = [float(s) for index, s in enumerate(scores) if index not in self.selected]
        max_other = max(others) if others else -1.0
        margin = (best_score - max_other) if others else 1.0

        # Untracked pre-detection filter (e.g. video recovery): test against references without mutating tracks
        if track_id is None or track_id <= 0:
            return best in self.selected and best_score >= SELECT_MIN_SIMILARITY and (not others or margin >= 0.05)

        # Strict bystander guard: if an unselected person is a better match, always reject
        if best not in self.selected or (others and best_score < max_other):
            if track_id in self.track_confirmed_counts:
                self.track_confirmed_counts[track_id] = 0
            return False

        # Case 1: Standard high-confidence match
        if best_score >= SELECT_MIN_SIMILARITY and margin >= 0.05:
            self.track_confirmed_counts[track_id] = self.track_confirmed_counts.get(track_id, 0) + 1
            hist = self.track_history.setdefault(track_id, [])
            hist.append(best_score)
            if len(hist) > 12:
                hist.pop(0)
            return True

        # Case 2: Temporal evidence for confirmed tracks during profile turns or lighting transitions
        # Track must have accumulated solid evidence (>= 3 confirmed frames, mean similarity >= 0.40)
        confirmed = self.track_confirmed_counts.get(track_id, 0)
        hist = self.track_history.get(track_id, [])
        if confirmed >= 3 and hist and float(np.mean(hist)) >= 0.40:
            # Tolerates momentary dip down to 0.28 if no unselected person is close
            if best_score >= 0.28 and margin >= 0.02:
                hist.append(best_score)
                if len(hist) > 12:
                    hist.pop(0)
                return True

        # Otherwise unconfirmed or insufficient margin
        self.track_confirmed_counts[track_id] = 0
        return False

    def missing_count(self, faces, chosen, embed):
        # Count rejected selected-looking faces without inferring that a
        # reference corresponds to a person present in every frame.
        chosen_ids = {id(face) for face in chosen}
        count = 0
        for face in faces:
            if id(face) in chosen_ids:
                continue
            vector = embed(face)
            if vector is None:
                continue
            scores = self.references @ vector
            index = int(np.argmax(scores))
            if index in self.selected and scores[index] >= 0.28:
                count += 1
        return count
