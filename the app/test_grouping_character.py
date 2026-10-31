"""Drawn characters go through the same grouping step as people, with 768-d CCIP embeddings and
their own thresholds. Synthetic vectors only: no models, no library."""
import base64
import unittest

import numpy as np

import grouping_core as gc


def enc(v):
    v = np.asarray(v, dtype="<f4")
    return base64.b64encode((v / np.linalg.norm(v)).astype("<f4").tobytes()).decode("ascii")


def character(rng, centre, n, start, noise=0.06):
    return [{"id": start + i, "embedding": enc(centre + rng.normal(0, noise, centre.shape)),
             "quality": 0.9, "frame_key": f"m{start + i}:", "rejected_person_ids": []} for i in range(n)]


def request(pending, models=(), strictness="character", mode="apply", stages=("match", "cluster")):
    return {"mode": mode, "stages": list(stages), "strictness": strictness, "models": list(models),
            "pending": pending, "dismissed_face_ids": [], "distinct_pairs": [], "bodies": []}


class CharacterGroupingTests(unittest.TestCase):
    def setUp(self):
        rng = np.random.default_rng(7)
        self.rng = rng
        self.a = rng.normal(0, 1, 768)
        self.b = rng.normal(0, 1, 768)

    def test_two_characters_become_two_groups(self):
        pending = character(self.rng, self.a, 5, 100) + character(self.rng, self.b, 5, 200)
        plan = gc.plan_request(request(pending))
        groups = sorted(sorted(g["face_ids"]) for g in plan["groups"])
        self.assertEqual(groups, [[100, 101, 102, 103, 104], [200, 201, 202, 203, 204]])
        self.assertTrue(all(g["auto_create"] for g in plan["groups"]))

    def test_a_known_character_claims_its_new_faces_only(self):
        model = {"pid": 7, "proto": enc(self.a),
                 "members": [enc(self.a + self.rng.normal(0, .06, 768)) for _ in range(4)], "count": 4}
        pending = character(self.rng, self.a, 2, 10) + character(self.rng, self.b, 2, 20)
        plan = gc.plan_request(request(pending, [model], stages=("match",)))
        self.assertEqual(sorted(a["face_id"] for a in plan["assignments"] if a["decision"] == "auto"), [10, 11])

    def test_the_embedding_size_follows_the_profile(self):
        pending = character(self.rng, self.a, 3, 1)
        with self.assertRaises(gc.GroupingRequestError):
            gc.plan_request(request(pending, strictness="balanced"))  # 768 values for a people plan
        people = [{"id": 1, "embedding": enc(np.ones(512)), "quality": .9, "frame_key": None,
                   "rejected_person_ids": []}]
        with self.assertRaises(gc.GroupingRequestError):
            gc.plan_request(request(people, strictness="character"))  # 512 values for a character plan


if __name__ == "__main__":
    unittest.main(verbosity=2)
