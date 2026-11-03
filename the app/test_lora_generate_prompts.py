"""Tests for vertical aspect ratio calculation and full body prompts in lora_generate.py"""
from lora_generate import (
    FULL_BODY_PROMPT_TEMPLATE,
    FULL_BODY_NEGATIVE_PROMPT,
    FULL_BODY_ANGLES,
    resolve_generation_dimensions
)

def test_full_body_templates():
    assert "{trigger}" in FULL_BODY_PROMPT_TEMPLATE
    assert "full length" in FULL_BODY_PROMPT_TEMPLATE or "full body" in FULL_BODY_PROMPT_TEMPLATE
    assert "feet" in FULL_BODY_PROMPT_TEMPLATE or "shoes" in FULL_BODY_PROMPT_TEMPLATE
    assert "bad anatomy" in FULL_BODY_NEGATIVE_PROMPT
    assert len(FULL_BODY_ANGLES) >= 4

def test_resolve_dimensions():
    # Square portrait default
    assert resolve_generation_dimensions("portrait_square") == (512, 512)
    # Vertical portrait
    assert resolve_generation_dimensions("portrait_vertical") == (512, 768)
    # Full body vertical (8:5 ratio)
    assert resolve_generation_dimensions("full_body") == (512, 768)
    # Full body tall
    assert resolve_generation_dimensions("full_body_tall") == (512, 896)

if __name__ == "__main__":
    test_full_body_templates()
    test_resolve_dimensions()
    print("Task 2 tests passed successfully!")
