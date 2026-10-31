"""Unit tests for AnimeFaceDetector (YOLOv8 anime face detection)."""
import os
import unittest
import numpy as np

from anime_detector import (
    AnimeFaceDetector,
    letterbox,
    decode_yolo,
    MIN_FACE_AR,
    MAX_FACE_AR,
    MIN_FACE_PX,
)


class TestAnimeDetector(unittest.TestCase):
    def test_letterbox_shapes(self):
        # 1000x500 image letterboxed to 640x640
        img = np.zeros((500, 1000, 3), dtype=np.uint8)
        canvas, scale, pad_x, pad_y = letterbox(img, 640)
        self.assertEqual(canvas.shape, (640, 640, 3))
        # 1000 scaled to 640 -> scale = 0.64
        self.assertAlmostEqual(scale, 0.64, places=2)
        # nh = 500 * 0.64 = 320 -> pad_y = (640 - 320) // 2 = 160
        self.assertEqual(pad_x, 0)
        self.assertEqual(pad_y, 160)

    def test_decode_yolo_geometry_filters(self):
        # Create synthetic output [1, 5, 4] (channel-major)
        # Anchor 0: Valid roughly square face (w=100, h=100, score=0.9)
        # Anchor 1: Thin vertical sliver (w=10, h=100 -> ar=0.1, score=0.9) - should be dropped
        # Anchor 2: Wide text banner (w=300, h=50 -> ar=6.0, score=0.9) - should be dropped
        # Anchor 3: Tiny icon (w=10, h=10 -> <20px, score=0.9) - should be dropped
        mat = np.zeros((1, 5, 4), dtype=np.float32)
        # Anchor 0 (valid)
        mat[0, 0, 0] = 320.0  # cx
        mat[0, 1, 0] = 320.0  # cy
        mat[0, 2, 0] = 100.0  # w
        mat[0, 3, 0] = 100.0  # h
        mat[0, 4, 0] = 0.90   # score

        # Anchor 1 (ar = 0.1 < 0.35)
        mat[0, 0, 1] = 100.0
        mat[0, 1, 1] = 100.0
        mat[0, 2, 1] = 10.0
        mat[0, 3, 1] = 100.0
        mat[0, 4, 1] = 0.90

        # Anchor 2 (ar = 6.0 > 1.8)
        mat[0, 0, 2] = 200.0
        mat[0, 1, 2] = 200.0
        mat[0, 2, 2] = 300.0
        mat[0, 3, 2] = 50.0
        mat[0, 4, 2] = 0.90

        # Anchor 3 (min_dim = 10 < 20)
        mat[0, 0, 3] = 400.0
        mat[0, 1, 3] = 400.0
        mat[0, 2, 3] = 10.0
        mat[0, 3, 3] = 10.0
        mat[0, 4, 3] = 0.90

        boxes, scores = decode_yolo(mat, score_thresh=0.55)
        self.assertEqual(len(boxes), 1)
        self.assertEqual(len(scores), 1)
        self.assertAlmostEqual(scores[0], 0.90, places=2)
        # [x1, y1, x2, y2] = [320 - 50, 320 - 50, 320 + 50, 320 + 50]
        self.assertEqual(boxes[0], [270.0, 270.0, 370.0, 370.0])

    def test_detector_with_model(self):
        model_path = os.path.join(os.path.dirname(__file__), "models", "anime_face_detect.onnx")
        if not os.path.exists(model_path):
            self.skipTest("anime_face_detect.onnx not found")
        detector = AnimeFaceDetector(model_path)
        # Run on a blank image; should return empty list without crashing
        blank = np.zeros((480, 640, 3), dtype=np.uint8)
        dets = detector.detect(blank)
        self.assertIsInstance(dets, list)


if __name__ == "__main__":
    unittest.main()
