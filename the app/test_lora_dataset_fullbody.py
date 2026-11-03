"""Tests for full-body crop categorization and shot-type captioning in lora_dataset.py"""
import numpy as np
from lora_dataset import classify_shot_type, build_caption

def test_classify_shot_type():
    # Synthetic whole image (1000x800: height=1000, width=800)
    image_shape = (1000, 800)
    
    # Small face box [x1, y1, x2, y2] - height = 120 / 1000 = 0.12
    face_box = [350, 100, 450, 220]
    assert classify_shot_type(face_box, image_shape) == "close-up portrait"
    
    # Upper body box (from top to mid-torso: height = 470 / 1000 = 0.47)
    upper_box = [200, 80, 600, 550]
    assert classify_shot_type(upper_box, image_shape) == "upper body shot"
    
    # Full body box (height = 900 / 1000 = 0.90 >= 0.70)
    full_box = [150, 50, 650, 950]
    assert classify_shot_type(full_box, image_shape) == "full length shot"

def test_caption_contains_shot_type():
    crop = np.zeros((768, 512, 3), dtype=np.uint8)
    caption = build_caption(crop, trigger_word="sks1", quality_score=0.9, shot_type="full length shot")
    assert "full length shot of sks1 person" in caption

if __name__ == "__main__":
    test_classify_shot_type()
    test_caption_contains_shot_type()
    print("Task 1 tests passed successfully!")
