"""Drawn (anime/cartoon) faces never become people. CPU only; no models, network or library."""
import re
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np

import drawn_faces
from analysis import AnalyzeOptions, analyze_frame
from test_character_detection import body, drawing

DART = Path(__file__).resolve().parent.parent / "mobile/lib/domain/scan/drawn_faces.dart"
DRAWN = drawn_faces._direction.astype(np.float32)


def real_embedding(seed=1):
    """A unit vector orthogonal to the drawn direction (score 0)."""
    v = np.random.default_rng(seed).normal(size=512)
    v -= (v @ drawn_faces._direction) * drawn_faces._direction
    return (v / np.linalg.norm(v)).astype(np.float32)


def face(box, embedding):
    return SimpleNamespace(bbox=np.array(box, np.float32), det_score=.9, kps=None, embedding=embedding)


class Bodies:
    available = True

    def __init__(self, *boxes):
        self.boxes = boxes

    def analyze(self, img, score_thr):
        return [body(b) for b in self.boxes]


class DrawnFaceTests(unittest.TestCase):
    def test_phone_uses_the_same_direction_and_threshold(self):
        dart = DART.read_text(encoding="utf-8")
        b64 = "".join(re.findall(r"'([A-Za-z0-9+/=]+)'", dart.split("const _directionB64 =")[1].split(";")[0]))
        self.assertEqual(b64, drawn_faces.DIRECTION_B64)
        threshold = float(re.search(r"const drawnFaceMinScore = ([0-9.]+);", dart).group(1))
        self.assertEqual(threshold, drawn_faces.DRAWN_MIN_SCORE)

    def test_score_is_a_cosine_and_bad_input_is_not_drawn(self):
        self.assertAlmostEqual(np.linalg.norm(drawn_faces._direction), 1, places=5)
        self.assertAlmostEqual(drawn_faces.drawn_score(DRAWN * 23), 1, places=5)  # raw embedding length
        self.assertAlmostEqual(drawn_faces.drawn_score(real_embedding()), 0, places=5)
        for bad in (None, np.zeros(512), np.ones(128), np.full(512, np.nan)):
            self.assertFalse(drawn_faces.is_drawn(bad))
        mixed = real_embedding() + (drawn_faces.DRAWN_MIN_SCORE + .01) / np.sqrt(1 - .21 ** 2) * DRAWN
        self.assertTrue(drawn_faces.is_drawn(mixed))

    def test_a_drawn_face_and_its_body_are_dropped_in_a_normal_scan(self):
        faces = [face((40, 10, 88, 72), DRAWN), face((300, 10, 348, 72), real_embedding())]
        result = analyze_frame(None, Bodies((0, 0, 128, 256), (256, 0, 384, 256)), wide(), AnalyzeOptions(),
                               detect=lambda _: faces, assess=lambda img, f: {"quality_score": .9})
        self.assertEqual(len(result.faces), 1)
        self.assertIs(result.faces[0], faces[1])
        self.assertEqual((len(result.quality), result.passes_gate), (1, [True]))
        self.assertEqual([list(b.bbox) for b in result.bodies], [[256, 0, 384, 256]])
        self.assertEqual(len(result.appearances), 1)
        self.assertEqual([(fi, bi) for fi, bi, _ in result.pairs], [(0, 0)])

    def test_a_good_drawn_face_does_not_hide_its_character(self):
        """The old rule took any face of quality >= 0.50 as real; drawn faces score 0.7-0.9."""
        options = AnalyzeOptions(detect_bodies=False, detect_characters=True)
        drawn = analyze_frame(None, Bodies((0, 0, 128, 256)), drawing(), options,
                              detect=lambda _: [face((40, 10, 88, 72), DRAWN)],
                              assess=lambda img, f: {"quality_score": .9})
        self.assertEqual((drawn.faces, len(drawn.characters)), ([], 1))
        real = analyze_frame(None, Bodies((0, 0, 128, 256)), drawing(), options,
                             detect=lambda _: [face((40, 10, 88, 72), real_embedding())],
                             assess=lambda img, f: {"quality_score": .9})
        self.assertEqual((len(real.faces), real.characters), (1, []))


def wide():
    return np.hstack([drawing(), np.full((256, 128, 3), 245, np.uint8), drawing()])


if __name__ == "__main__":
    unittest.main(verbosity=2)
