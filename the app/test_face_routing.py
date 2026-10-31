"""Unit tests for face routing and baby-face veto logic."""
import unittest

from face_routing import (
    box_iou,
    box_containment,
    overlaps_real_face,
    route_detections,
)


class TestFaceRouting(unittest.TestCase):
    def test_box_iou(self):
        b1 = [0.0, 0.0, 100.0, 100.0]  # area = 10000
        b2 = [50.0, 0.0, 150.0, 100.0]  # inter = 50*100 = 5000, union = 15000 -> iou = 1/3
        iou = box_iou(b1, b2)
        self.assertAlmostEqual(iou, 1.0 / 3.0, places=4)

        # Identical boxes
        self.assertAlmostEqual(box_iou(b1, b1), 1.0, places=4)

        # Disjoint boxes
        b3 = [200.0, 200.0, 300.0, 300.0]
        self.assertEqual(box_iou(b1, b3), 0.0)

    def test_box_containment(self):
        # b2 is a smaller box fully inside b1
        b1 = [0.0, 0.0, 200.0, 200.0]  # area = 40000
        b2 = [50.0, 50.0, 100.0, 100.0]  # area = 2500, inter = 2500
        # IoU = 2500 / 40000 = 0.0625 (< 0.5)
        # But b2 is 100% contained in b1 -> containment = 1.0
        self.assertLess(box_iou(b1, b2), 0.1)
        self.assertAlmostEqual(box_containment(b1, b2), 1.0, places=4)

    def test_overlaps_real_face_veto(self):
        # Case 1: High IoU (>= 0.5)
        real = [100.0, 100.0, 200.0, 200.0]
        anime = [110.0, 100.0, 205.0, 200.0]
        self.assertTrue(overlaps_real_face(real, anime))

        # Case 2: One box contains the other (Containment >= 0.6)
        real_tight = [100.0, 100.0, 180.0, 180.0]
        anime_wide = [80.0, 80.0, 200.0, 200.0]  # anime contains real
        self.assertTrue(overlaps_real_face(real_tight, anime_wide))

        # Case 3: Distinct different persons in same image
        real_person1 = [50.0, 50.0, 120.0, 120.0]
        anime_poster = [300.0, 300.0, 380.0, 380.0]
        self.assertFalse(overlaps_real_face(real_person1, anime_poster))

    def test_route_detections_baby_veto(self):
        # Baby face detected by both: SCRFD detected at 0.55 (above veto 0.40),
        # Anime detector falsely fired at 0.75.
        real_dets = [
            {"bbox": [100.0, 100.0, 200.0, 200.0], "score": 0.55}  # baby
        ]
        anime_dets = [
            {"bbox": [105.0, 105.0, 195.0, 195.0], "score": 0.75}
        ]

        routed_real, routed_anime = route_detections(
            real_dets, anime_dets, real_scan_thresh=0.50, real_veto_thresh=0.40
        )
        # Anime detection must be vetoed
        self.assertEqual(len(routed_anime), 0)
        # Real face must be kept
        self.assertEqual(len(routed_real), 1)

    def test_route_detections_genuine_anime(self):
        # Genuine anime: Anime detector fired at 0.85, SCRFD either didn't fire or < 0.40
        real_dets = []
        anime_dets = [
            {"bbox": [100.0, 100.0, 200.0, 200.0], "score": 0.85}
        ]

        routed_real, routed_anime = route_detections(
            real_dets, anime_dets, real_scan_thresh=0.50, real_veto_thresh=0.40
        )
        self.assertEqual(len(routed_real), 0)
        self.assertEqual(len(routed_anime), 1)


if __name__ == "__main__":
    unittest.main()
