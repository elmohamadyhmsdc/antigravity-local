"""Tests for face-detailer post-processing pass on full-body images"""
import numpy as np
from PIL import Image
from lora_generate import apply_face_detailer

def test_face_detailer_preserves_full_image_dimensions():
    # Create synthetic full-body canvas (512 x 768: width=512, height=768)
    canvas = np.zeros((768, 512, 3), dtype=np.uint8)
    # Draw a synthetic face blob at head position (x: 230-280, y: 50-110)
    canvas[50:110, 230:280] = 180
    pil_img = Image.fromarray(canvas)
    
    enhanced = apply_face_detailer(pil_img, face_restorer=None)
    assert enhanced.size == (512, 768)

if __name__ == "__main__":
    test_face_detailer_preserves_full_image_dimensions()
    print("Task 4 tests passed successfully!")
