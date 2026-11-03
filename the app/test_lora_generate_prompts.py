"""Tests for vertical aspect ratio calculation and full body prompts in lora_generate.py"""
from lora_generate import (
    ANGLE_PROMPTS,
    PORTRAIT_ANGLES,
    angle_description,
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

def test_named_head_angles_win_and_resume_where_an_interrupted_run_stopped():
    names = ["profile", "profile", "three_quarter", "up"]
    request = {"angles": names}
    assert [angle_description(request, PORTRAIT_ANGLES, i, False) for i in range(4)] == [ANGLE_PROMPTS[n] for n in names]
    # the run made two images before it was interrupted: the resumed one continues the list
    resumed = {"angles": names, "angle_offset": 2}
    assert angle_description(resumed, PORTRAIT_ANGLES, 0, False) == ANGLE_PROMPTS["three_quarter"]
    assert angle_description(resumed, PORTRAIT_ANGLES, 1, False) == ANGLE_PROMPTS["up"]
    # a single image still gets its angle (the old multi_angle rule needed several images)
    assert angle_description({"angles": ["down"]}, PORTRAIT_ANGLES, 0, False) == ANGLE_PROMPTS["down"]


def test_without_angles_the_old_rotation_is_unchanged():
    assert angle_description({}, PORTRAIT_ANGLES, 1, True) == PORTRAIT_ANGLES[1]
    assert angle_description({}, PORTRAIT_ANGLES, len(PORTRAIT_ANGLES), True) == PORTRAIT_ANGLES[0]
    assert angle_description({}, PORTRAIT_ANGLES, 0, False) is None


if __name__ == "__main__":
    test_full_body_templates()
    test_resolve_dimensions()
    test_named_head_angles_win_and_resume_where_an_interrupted_run_stopped()
    test_without_angles_the_old_rotation_is_unchanged()
    print("Task 2 tests passed successfully!")
