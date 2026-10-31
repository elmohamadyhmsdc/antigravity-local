"""Unit tests for CCIP character embedder and appearance features."""
import os
import unittest
import numpy as np

from character_embedder import (
    CcipEmbedder,
    asymmetric_ccip_crop,
    extract_hat_hue,
    extract_outfit_hue,
    CCIP_DIM,
    OUTFIT_DIM,
    HAT_DIM,
    TOTAL_APPEARANCE_DIM,
)


class TestCharacterEmbedder(unittest.TestCase):
    def test_crop_math(self):
        # 1000x1000 image, face box [400, 400, 600, 600] -> w=200, h=200
        # l = 400 - 200*0.5 = 300
        # t = 400 - 200*0.8 = 240
        # r = 600 + 200*0.5 = 700
        # b = 600 + 200*1.2 = 840
        bbox = [400.0, 400.0, 600.0, 600.0]
        l, t, r, b = asymmetric_ccip_crop(bbox, 1000, 1000)
        self.assertEqual((l, t, r, b), (300, 240, 700, 840))

    def test_hue_feature_dimensions(self):
        img = np.zeros((500, 500, 3), dtype=np.uint8)
        # Red square for hat, blue square for outfit
        img[50:150, 100:300] = [0, 0, 255]  # Red in BGR
        img[300:450, 100:300] = [255, 0, 0]  # Blue in BGR
        bbox = [100.0, 150.0, 300.0, 300.0]

        hat = extract_hat_hue(img, bbox)
        self.assertEqual(len(hat), HAT_DIM)
        outfit = extract_outfit_hue(img, bbox)
        self.assertEqual(len(outfit), OUTFIT_DIM)

    def test_ccip_embedder_with_model(self):
        model_path = os.path.join(os.path.dirname(__file__), "models", "ccip_character.onnx")
        if not os.path.exists(model_path):
            self.skipTest("ccip_character.onnx not found")

        embedder = CcipEmbedder(model_path)
        img = np.random.randint(0, 255, (400, 400, 3), dtype=np.uint8)
        bbox = [100.0, 100.0, 250.0, 250.0]

        vec = embedder.embed(img, bbox)
        self.assertEqual(len(vec), TOTAL_APPEARANCE_DIM)
        # Check normalized
        norm = np.linalg.norm(vec[:CCIP_DIM])
        self.assertAlmostEqual(norm, 1.0, places=3)


if __name__ == "__main__":
    unittest.main()
