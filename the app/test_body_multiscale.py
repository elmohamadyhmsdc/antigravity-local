"""Zoomed-window body detection and face-guided recovery (no GPU, no models: the detector is a fake)."""
import unittest

import numpy as np

from body_detector import Body, BodyAnalyzer, merge_person_boxes, tile_windows


class _Detector:
    """Sees a person only when it is at least `min_px` tall in the picture it is given."""

    def __init__(self, persons, min_px=60):
        self.persons, self.min_px, self.calls = persons, min_px, []

    def _raw(self, img, thr):
        self.calls.append(img.shape[:2])
        out = []
        h, w = img.shape[:2]
        scale = 640 / max(h, w)
        # persons are given in the coordinates of the picture the analyzer started with (offset by the window)
        for (x1, y1, x2, y2) in self.persons:
            ox, oy = getattr(self, "offset", (0, 0))
            box = np.array([x1 - ox, y1 - oy, x2 - ox, y2 - oy], np.float32)
            if box[0] < 0 or box[1] < 0 or box[2] > w or box[3] > h:
                continue
            if (box[3] - box[1]) * scale >= self.min_px * 0.4:
                out.append([*box, 0.9])
        return np.array(out, np.float32).reshape(-1, 5)


class Windows(unittest.TestCase):
    def test_windows_cover_the_picture_with_overlap(self):
        wins = tile_windows(2560, 1920, 1024, 0.25)
        self.assertEqual(len({(x, y) for x, y, _, _ in wins}), len(wins))
        covered = np.zeros((1920, 2560), bool)
        for x, y, tw, th in wins:
            covered[y:y + th, x:x + tw] = True
        self.assertTrue(covered.all())
        self.assertTrue(all(tw <= 1024 and th <= 1024 for _, _, tw, th in wins))
        xs = sorted({x for x, _, _, _ in wins})
        self.assertTrue(all(b - a < 1024 for a, b in zip(xs, xs[1:])), "neighbours overlap")

    def test_a_small_picture_is_one_window(self):
        self.assertEqual(tile_windows(800, 600, 1024), [(0, 0, 800, 600)])


class Merging(unittest.TestCase):
    def test_same_person_at_two_scales_is_one_box(self):
        dets = np.array([[100, 100, 200, 400, 0.9], [102, 98, 198, 404, 0.7]], np.float32)
        merged = merge_person_boxes(dets)
        self.assertEqual(len(merged), 1)
        self.assertAlmostEqual(float(merged[0, 4]), 0.9, places=5)

    def test_a_torso_inside_a_stronger_box_is_dropped_but_a_neighbour_stays(self):
        dets = np.array([[100, 100, 300, 600, 0.9], [120, 150, 280, 350, 0.8], [320, 100, 520, 600, 0.6]], np.float32)
        merged = merge_person_boxes(dets)
        self.assertEqual(sorted(merged[:, 0].tolist()), [100.0, 320.0])


class Recovery(unittest.TestCase):
    def _analyzer(self, persons, **kw):
        ba = BodyAnalyzer(use_pose=False, **kw)
        ba._loaded = True
        ba.detector = _Detector(persons)
        return ba

    def test_a_small_person_the_full_view_missed_is_found_around_its_face(self):
        img = np.zeros((1920, 2560, 3), np.uint8)
        person = (1000, 800, 1090, 1100)            # 300 px tall in a 1920 px picture
        face = np.array([1020, 800, 1070, 860], np.float32)
        ba = self._analyzer([person])
        ba.detector.offset = (0, 0)
        # the window the analyzer will cut, so the fake can place the person in it
        def raw(window, thr):
            wx = 1045 - 3.5 * 60
            ba.detector.calls.append(window.shape[:2])
            return np.array([[person[0] - int(wx), person[1] - int(max(0, 800 - 1.2 * 60)),
                              person[2] - int(wx), person[3] - int(max(0, 800 - 1.2 * 60)), 0.8]], np.float32)
        ba.detector._raw = raw
        found = ba.recover_for_faces(img, [face], [], 0.5)
        self.assertEqual(len(found), 1)
        self.assertLess(abs(float(found[0].bbox[1]) - person[1]), 3)
        self.assertLess(abs(float(found[0].bbox[3]) - person[3]), 3)

    def test_a_face_that_already_has_a_body_triggers_no_extra_look(self):
        img = np.zeros((1000, 1000, 3), np.uint8)
        body = Body(bbox=np.array([100, 100, 300, 700], np.float32), score=0.9)
        face = np.array([160, 110, 240, 190], np.float32)
        ba = self._analyzer([])
        out = ba.recover_for_faces(img, [face], [body], 0.5)
        self.assertEqual(out, [body])
        self.assertEqual(ba.detector.calls, [])

    def test_a_close_up_or_a_speck_is_left_alone(self):
        img = np.zeros((1000, 1000, 3), np.uint8)
        ba = self._analyzer([])
        ba.recover_for_faces(img, [np.array([100, 100, 105, 108], np.float32),       # 8 px: a speck
                                   np.array([200, 100, 700, 700], np.float32)], [], 0.5)   # fills the picture
        self.assertEqual(ba.detector.calls, [])

    def test_a_recovered_box_replaces_an_unowned_body_it_covers(self):
        img = np.zeros((1200, 1200, 3), np.uint8)
        face = np.array([520, 300, 580, 370], np.float32)
        # a box over the legs only: it does not hold the face, so it owns nothing
        legs = Body(bbox=np.array([480, 520, 620, 700], np.float32), score=0.55)
        unrelated = Body(bbox=np.array([20, 20, 100, 300], np.float32), score=0.9)
        ba = self._analyzer([])
        # the window starts at (550 - 3.5*70, 300 - 1.2*70) = (305, 216); the person fills most of it
        ba.detector._raw = lambda window, thr: np.array([[170, 60, 330, 480, 0.8]], np.float32)
        out = ba.recover_for_faces(img, [face], [legs, unrelated], 0.5)
        self.assertEqual(len(out), 2)
        self.assertTrue(any(b is unrelated for b in out), "an unrelated body is untouched")
        self.assertFalse(any(b is legs for b in out), "the legs-only box was the same person and is replaced")
        recovered = next(b for b in out if b is not unrelated)
        self.assertLess(abs(float(recovered.bbox[1]) - 276), 3)


if __name__ == "__main__":
    unittest.main()
