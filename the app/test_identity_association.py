"""CPU-only face/body attribution regressions; no models or library access."""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np

import person_linking as pl


class IdentityAssociationTests(unittest.TestCase):
    def associate(self, scores):
        bodies = [SimpleNamespace(bbox=i) for i in range(len(scores[0]))]
        with patch.object(pl, "face_body_score", side_effect=lambda f, b, *_: scores[f][b]):
            return pl.associate_faces_bodies(range(len(scores)), bodies)

    def test_near_tied_overlapping_bodies_remain_unlinked(self):
        self.assertEqual(self.associate([[0.91, 0.90], [0.90, 0.91]]), [])

    def test_joint_assignment_can_use_a_locally_second_best_edge(self):
        pairs = self.associate([[0.95, 0.90], [0.89, 0.1]])
        self.assertEqual([p[:2] for p in pairs], [(0, 1), (1, 0)])

    def test_ambiguity_does_not_drop_an_unrelated_clear_person(self):
        pairs = self.associate([[0.9, 0.9, 0], [0.9, 0.9, 0], [0, 0, 0.95]])
        self.assertEqual([p[:2] for p in pairs], [(2, 2)])

    def test_invalid_and_subthreshold_pairs_do_not_displace_a_valid_face(self):
        pairs = self.associate([[np.nan, 0.34], [np.inf, 0.95], [0.1, 0.0]])
        self.assertEqual([p[:2] for p in pairs], [(1, 1)])

    def test_pose_head_disambiguates_overlapping_boxes(self):
        def body(head):
            kpts = np.zeros((17, 2), dtype=np.float32)
            kpts[:5] = head
            scores = np.zeros(17, dtype=np.float32)
            scores[:5] = 0.95
            return SimpleNamespace(bbox=[0, 0, 220, 400], kpts=kpts, kpt_scores=scores)
        pairs = pl.associate_faces_bodies(
            [[20, 10, 70, 70], [140, 10, 190, 70]],
            [body([165, 35]), body([45, 35])],
        )
        self.assertEqual([p[:2] for p in pairs], [(0, 1), (1, 0)])


if __name__ == "__main__":
    unittest.main()
