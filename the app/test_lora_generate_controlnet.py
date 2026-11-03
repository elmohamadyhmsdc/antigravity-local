"""Tests for loading and preparing ControlNet OpenPose in lora_generate.py"""
import numpy as np
from PIL import Image
from lora_generate import prepare_pose_condition, is_controlnet_available

def test_controlnet_readiness():
    assert is_controlnet_available() is True

def test_prepare_pose_condition():
    # Synthetic RGB pose image (768x512)
    dummy_pose = Image.fromarray(np.zeros((768, 512, 3), dtype=np.uint8))
    cond_image = prepare_pose_condition(dummy_pose, target_size=(512, 768))
    assert cond_image.size == (512, 768)

if __name__ == "__main__":
    test_controlnet_readiness()
    test_prepare_pose_condition()
    print("Task 3 tests passed successfully!")
