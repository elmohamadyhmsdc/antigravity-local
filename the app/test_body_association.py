r"""CPU-only regressions for neighbouring people and face/body association.

No model loading, downloads, server, GPU, database or personal media.
Run with the existing main environment from the app directory:
    .\venv\Scripts\python.exe test_body_association.py
"""

from types import SimpleNamespace
import unittest

import numpy as np

import person_linking as pl


def body_with_head(box, centre, score=0.9, count=5):
    points = np.zeros((17, 2), dtype=np.float32)
    scores = np.zeros(17, dtype=np.float32)
    x, y = centre
    for i, (dx, dy) in enumerate(((0, 0), (-5, -4), (5, -4), (-10, -2), (10, -2))):
        points[i] = (x + dx, y + dy)
        scores[i] = score if i < count else 0.0
    return SimpleNamespace(bbox=np.asarray(box, dtype=np.float32), score=0.9,
                           kpts=points, kpt_scores=scores)


class BodyAssociationTests(unittest.TestCase):
    def test_confident_neighbour_head_rejects_a_contained_face(self):
        # A wide overlapping box contains the left face, but its head is right.
        body = body_with_head((0, 0, 240, 320), (180, 40))
        neighbour = np.array((40, 20, 80, 60), dtype=np.float32)
        self.assertEqual(pl.face_body_score(neighbour, body.bbox, None,
                                           body.kpts, body.kpt_scores), 0.0)
        self.assertEqual(pl.associate_faces_bodies([neighbour], [body]), [])

    def test_missing_pose_retains_geometry_fallback(self):
        face = np.array((40, 20, 80, 60), dtype=np.float32)
        body = SimpleNamespace(bbox=np.array((0, 0, 240, 320), dtype=np.float32))
        self.assertGreaterEqual(pl.face_body_score(face, body.bbox), 0.35)
        self.assertEqual(len(pl.associate_faces_bodies([face], [body])), 1)

    def test_low_confidence_head_does_not_become_a_hard_veto(self):
        face = np.array((40, 20, 80, 60), dtype=np.float32)
        body = body_with_head((0, 0, 240, 320), (180, 40), score=0.4)
        self.assertGreaterEqual(pl.face_body_score(face, body.bbox, None,
                                                  body.kpts, body.kpt_scores), 0.35)
        self.assertEqual(len(pl.associate_faces_bodies([face], [body])), 1)

    def test_only_two_confident_points_keep_the_existing_fallback(self):
        face = np.array((40, 20, 80, 60), dtype=np.float32)
        body = body_with_head((0, 0, 240, 320), (180, 40), count=2)
        self.assertGreaterEqual(pl.face_body_score(face, body.bbox, None,
                                                  body.kpts, body.kpt_scores), 0.35)

    def test_a_confident_point_inside_the_face_prevents_the_contradiction_veto(self):
        face = np.array((40, 20, 80, 60), dtype=np.float32)
        body = body_with_head((0, 0, 240, 320), (180, 40))
        body.kpts[0] = (60, 40)
        self.assertGreaterEqual(pl.face_body_score(face, body.bbox, None,
                                                  body.kpts, body.kpt_scores), 0.35)

    def test_overlapping_bodies_keep_their_own_heads_in_reverse_face_order(self):
        left = body_with_head((0, 0, 220, 320), (60, 40))
        right = body_with_head((20, 0, 240, 320), (180, 40))
        before = [b.bbox.copy() for b in (left, right)]
        faces = [np.array((160, 20, 200, 60), dtype=np.float32),
                 np.array((40, 20, 80, 60), dtype=np.float32)]
        pairs = pl.associate_faces_bodies(faces, [left, right])
        self.assertEqual({(f, b) for f, b, _ in pairs}, {(0, 1), (1, 0)})
        for body, box in zip((left, right), before):
            np.testing.assert_array_equal(body.bbox, box)

    def test_one_model_box_stays_one_body_and_pairs_with_at_most_one_face(self):
        body = body_with_head((0, 0, 240, 320), (180, 40))
        faces = [np.array((40, 20, 80, 60), dtype=np.float32),
                 np.array((160, 20, 200, 60), dtype=np.float32)]
        pairs = pl.associate_faces_bodies(faces, [body])
        self.assertEqual(len(pairs), 1)
        self.assertEqual(pairs[0][:2], (1, 0))

    def test_analysis_preserves_distinct_faceless_bodies_with_identical_outfits(self):
        from analysis import AnalyzeOptions, analyze_frame

        bodies = [SimpleNamespace(bbox=np.array(box, dtype=np.float32), score=0.9,
                                  kpts=None, kpt_scores=None)
                  for box in ((10, 10, 150, 310), (130, 10, 270, 310))]
        boxes_before = [b.bbox.copy() for b in bodies]

        class ScriptedBodies:
            available = True

            def analyze(self, img, score_thr=0.5):
                return bodies

        image = np.full((320, 280, 3), 128, dtype=np.uint8)
        result = analyze_frame(None, ScriptedBodies(), image, AnalyzeOptions(),
                               detect=lambda img: [])
        self.assertEqual(len(result.bodies), 2)
        self.assertEqual(result.pairs, [])
        self.assertTrue(all(a is not None for a in result.appearances))
        np.testing.assert_allclose(result.appearances[0], result.appearances[1])
        for actual, expected in zip(result.bodies, boxes_before):
            np.testing.assert_array_equal(actual.bbox, expected)


if __name__ == "__main__":
    unittest.main()
