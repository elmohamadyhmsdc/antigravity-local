"""
Antigravity Local - Magic Undress core tests

No GPU, no Hugging Face, no venv_ai. Pure undress_core behavior.

    venv\\Scripts\\python.exe test_undress.py
    venv\\Scripts\\python.exe test_undress.py mask
"""
import sys
import time
import traceback
from pathlib import Path

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


@test
def test_format_and_parse_result_ignores_leading_noise():
    from undress_core import format_result_line, parse_result_stdout

    payload = {"success": True, "output_image": "abc"}
    noisy = "Loading weights...\nFetching 18 files\n" + format_result_line(payload) + "\n"
    got = parse_result_stdout(noisy)
    check(got["success"] is True, f"success lost: {got}")
    check(got["output_image"] == "abc", f"payload mismatch: {got}")


@test
def test_parse_result_stdout_rejects_missing_marker():
    from undress_core import parse_result_stdout

    try:
        parse_result_stdout('{"success": true}\n')
    except ValueError as e:
        check("UNDRESS_RESULT" in str(e) or "marker" in str(e).lower(), f"unclear error: {e}")
    else:
        raise AssertionError("expected ValueError when the result marker is missing")


@test
def test_limited_size_is_multiple_of_64_and_never_zero():
    from undress_core import WORK_MAX_DIM, limited_size

    w, h = limited_size(2000, 1000, max_dim=1024, multiple=64)
    check(w % 64 == 0 and h % 64 == 0, f"not aligned: {w}x{h}")
    check(w <= 1024 and h <= 1024, f"exceeds max: {w}x{h}")
    dw, dh = limited_size(2000, 3000)
    check(max(dw, dh) <= WORK_MAX_DIM, f"default work size too large: {dw}x{dh}")
    check(w > 0 and h > 0, f"zero dim: {w}x{h}")

    tw, th = limited_size(50, 40, max_dim=1024, multiple=64)
    check(tw >= 64 and th >= 64, f"tiny image must upscale to at least 64: {tw}x{th}")
    check(tw % 64 == 0 and th % 64 == 0, f"tiny not aligned: {tw}x{th}")


@test
def test_fit_work_size_upsizes_a_small_crop_to_768():
    from undress_core import fit_work_size, WORK_MAX_DIM

    w, h = fit_work_size(200, 300)
    check(max(w, h) == WORK_MAX_DIM, f"long side should be {WORK_MAX_DIM}, got {w}x{h}")
    check(w % 64 == 0 and h % 64 == 0, f"not aligned: {w}x{h}")


@test
def test_scale_bbox_maps_original_coords_onto_resized_image():
    from undress_core import scale_bbox

    box = scale_bbox([100, 50, 300, 250], (1000, 500), (500, 250))
    check(box == [50, 25, 150, 125], f"got {box}")


@test
def test_expand_head_bbox_pads_up_more_than_down_and_clamps():
    from undress_core import expand_head_bbox

    x1, y1, x2, y2 = expand_head_bbox([40, 40, 80, 90], 200, 200)
    check(y1 < 40, f"should pad upward for hair, y1={y1}")
    check(y2 >= 90, f"should not shrink downward, y2={y2}")
    check(x1 <= 40 and x2 >= 80, f"should pad sideways, got {(x1, y1, x2, y2)}")

    top = expand_head_bbox([0, 0, 20, 20], 100, 100)
    check(top[0] >= 0 and top[1] >= 0, f"must clamp to image: {top}")
    check(top[2] <= 100 and top[3] <= 100, f"must clamp to image: {top}")


@test
def test_inpaint_mask_keeps_head_and_background_inpaints_body():
    import numpy as np
    from undress_core import build_inpaint_mask

    person = np.zeros((100, 80), np.uint8)
    person[20:90, 10:70] = 255  # torso + head
    face = [20, 20, 60, 50]     # head region inside the person

    mask = build_inpaint_mask(person, face, feather_px=1)
    check(mask.shape == (100, 80), f"shape {mask.shape}")
    check(mask[5, 5] == 0, "background must be keep (0)")
    check(mask[35, 40] < 40, f"face interior must be keep, got {mask[35, 40]}")
    check(mask[80, 40] > 200, f"torso must be inpaint, got {mask[80, 40]}")


@test
def test_inpaint_mask_keeps_hair_and_exposed_skin_inpaints_clothes():
    import numpy as np
    from undress_core import build_inpaint_mask

    h, w = 120, 80
    person = np.zeros((h, w), np.uint8)
    person[8:110, 12:68] = 255
    rgb = np.zeros((h, w, 3), np.uint8)
    rgb[:, :] = (20, 40, 200)              # blue background
    rgb[8:110, 12:68] = (25, 50, 170)      # blue garment on torso
    rgb[8:38, 18:62] = (42, 28, 22)        # dark hair
    rgb[28:52, 22:58] = (210, 168, 140)    # face skin
    rgb[55:100, 12:22] = (210, 168, 140)   # exposed arm skin
    face = [22, 28, 58, 52]

    mask = build_inpaint_mask(person, face, feather_px=1, image_rgb=rgb)
    check(mask[20, 40] < 40, f"hair must be kept, got {mask[20, 40]}")
    check(mask[38, 40] < 40, f"face skin must be kept, got {mask[38, 40]}")
    check(mask[75, 16] < 80, f"exposed arm skin must be kept, got {mask[75, 16]}")
    check(mask[80, 40] > 180, f"clothes must be inpaint, got {mask[80, 40]}")
    check(mask[5, 5] == 0, "background must stay keep")


@test
def test_torso_clothes_stay_inpaint_even_when_skin_tinted():
    import numpy as np
    from undress_core import build_inpaint_mask

    h, w = 120, 80
    person = np.zeros((h, w), np.uint8)
    person[8:110, 12:68] = 255
    rgb = np.zeros((h, w, 3), np.uint8)
    rgb[:, :] = (20, 40, 200)
    rgb[8:110, 12:68] = (186, 148, 122)    # warm beige dress — looks a bit like skin
    rgb[8:38, 18:62] = (42, 28, 22)        # hair
    rgb[28:52, 22:58] = (210, 168, 140)    # face
    rgb[55:100, 12:22] = (210, 168, 140)   # arm
    face = [22, 28, 58, 52]

    mask = build_inpaint_mask(person, face, feather_px=1, image_rgb=rgb)
    check(mask[38, 40] < 40, f"face must stay keep, got {mask[38, 40]}")
    check(mask[75, 16] < 80, f"arm must stay keep, got {mask[75, 16]}")
    check(mask[80, 40] > 180, f"dress torso must be inpaint, got {mask[80, 40]}")
    check(mask[62, 40] > 180, f"upper dress must be inpaint, got {mask[62, 40]}")


@test
def test_harden_inpaint_mask_drops_gray_leak_and_protects_hands():
    import numpy as np
    from undress_core import harden_inpaint_mask

    soft = np.zeros((40, 40), np.uint8)
    soft[8:32, 8:32] = 255
    soft[6:8, 8:32] = 90          # feathered edge — original dress would leak
    hands = np.zeros((40, 40), np.uint8)
    hands[24:36, 4:14] = 255
    hard = harden_inpaint_mask(soft, hard_keep=hands, dilate_px=3)
    check(set(np.unique(hard)).issubset({0, 255}), f"SD mask must be binary, got {np.unique(hard)}")
    check(hard[7, 20] == 255, "gray feather must become full inpaint for the model")
    check(hard[30, 8] == 0, "hands must stay keep on the model mask")


@test
def test_hanging_hair_is_kept_black_dress_is_not():
    import numpy as np
    from undress_core import build_inpaint_mask

    h, w = 120, 80
    person = np.zeros((h, w), np.uint8)
    person[8:110, 14:66] = 255
    rgb = np.zeros((h, w, 3), np.uint8)
    rgb[:, :] = (30, 50, 180)
    rgb[8:110, 14:66] = (18, 18, 18)       # black dress
    rgb[8:36, 22:58] = (48, 32, 24)        # brown hair on head
    rgb[36:70, 16:30] = (48, 32, 24)       # hair over the shoulder
    rgb[20:44, 26:54] = (210, 168, 140)    # face
    rgb[60:100, 50:64] = (210, 168, 140)   # arm
    face = [26, 20, 54, 44]

    mask = build_inpaint_mask(person, face, feather_px=1, image_rgb=rgb)
    check(mask[48, 22] < 80, f"shoulder hair must be kept, got {mask[48, 22]}")
    check(mask[90, 40] > 180, f"black dress must be inpaint, got {mask[90, 40]}")


@test
def test_spread_fingers_do_not_keep_the_dress_between_them():
    import numpy as np
    from undress_core import hands_keep_mask

    pts = np.zeros((21, 2), np.float32)
    pts[0] = (20, 70)
    pts[1:5] = [(18, 66), (14, 58), (11, 50), (9, 44)]
    mcps = [(18, 62), (22, 61), (26, 62), (30, 63)]
    tips = [(16, 34), (36, 28), (52, 30), (66, 38)]
    for f, (mcp, tip) in enumerate(zip(mcps, tips)):
        base = 5 + f * 4
        for j in range(4):
            t = j / 3.0
            pts[base + j] = (
                mcp[0] + t * (tip[0] - mcp[0]),
                mcp[1] + t * (tip[1] - mcp[1]),
            )
    mask = hands_keep_mask((90, 80), [pts])
    check(mask[70, 20] == 255, "palm must be keep")
    check(mask[28, 36] == 255, "middle fingertip must be keep")
    check(mask[30, 44] < 80, f"dress between spread fingers must not be keep, got {mask[30, 44]}")


@test
def test_hands_keep_mask_covers_palm_and_fingertips():
    import numpy as np
    from undress_core import hands_keep_mask

    h, w = 80, 80
    # 21 landmarks: wrist at (20, 50), fingers stretching toward (20, 12)
    pts = np.zeros((21, 2), np.float32)
    pts[0] = (20, 50)
    for i, x in enumerate((18, 16, 15, 14)):
        pts[1 + i] = (x, 46 - i * 6)
    for f, x in enumerate((18, 20, 22, 24)):
        base = 5 + f * 4
        for j in range(4):
            pts[base + j] = (x, 42 - j * 8)
    mask = hands_keep_mask((h, w), [pts])
    check(mask[50, 20] == 255, "palm/wrist must be keep")
    check(mask[18, 20] == 255, f"fingertip must be keep, got {mask[18, 20]}")
    check(mask[10, 70] == 0, "far background must stay empty")


@test
def test_inpaint_mask_keeps_hands_against_feather():
    import numpy as np
    from undress_core import build_inpaint_mask

    person = np.full((80, 80), 255, np.uint8)
    extra = np.zeros((80, 80), np.uint8)
    extra[50:70, 8:28] = 255  # hand overlapping the body
    face = [30, 8, 55, 32]
    mask = build_inpaint_mask(person, face, feather_px=21, extra_keep=extra)
    check(mask[60, 18] == 0, f"hand pixel must stay hard-keep after feather, got {mask[60, 18]}")
    check(mask[75, 50] > 180, f"torso away from hand must stay inpaint, got {mask[75, 50]}")


@test
def test_exposed_skin_keeps_hands_darker_than_the_face():
    import numpy as np
    from undress_core import exposed_skin_mask

    h, w = 100, 80
    person = np.zeros((h, w), np.uint8)
    person[10:95, 10:70] = 255
    rgb = np.zeros((h, w, 3), np.uint8)
    rgb[10:95, 10:70] = (20, 40, 160)      # clothes
    rgb[12:40, 24:56] = (210, 168, 140)    # face
    rgb[70:92, 12:28] = (118, 78, 58)      # shadowed hand, darker than face
    face = [24, 12, 56, 40]
    skin = exposed_skin_mask(rgb, person, face)
    check(skin[26, 40] == 255, f"face skin must be kept, got {skin[26, 40]}")
    check(skin[80, 18] == 255, f"darker hand must be kept, got {skin[80, 18]}")
    check(skin[55, 40] == 0, "clothes must not be marked as skin")


@test
def test_composite_keeps_original_pixels_outside_the_inpaint_mask():
    import numpy as np
    from undress_core import composite_inpaint

    orig = np.full((16, 16, 3), 11, np.uint8)
    gen = np.full((16, 16, 3), 200, np.uint8)
    mask = np.zeros((16, 16), np.uint8)
    mask[:, 8:] = 255
    out = composite_inpaint(orig, gen, mask)
    check(tuple(out[8, 2]) == (11, 11, 11), f"kept pixel mutated: {out[8, 2]}")
    check(tuple(out[8, 14]) == (200, 200, 200), f"inpaint pixel not taken from gen: {out[8, 14]}")


@test
def test_harmonize_moves_generated_skin_toward_original_skin():
    import numpy as np
    from undress_core import harmonize_generated_region

    orig = np.zeros((32, 32, 3), np.uint8)
    orig[:, :] = (40, 40, 40)
    orig[8:16, 4:12] = (210, 165, 135)    # original skin (kept)
    gen = orig.copy()
    gen[8:16, 12:24] = (250, 200, 170)    # generated skin, adjacent, too pale
    gen[22:30, 8:24] = (250, 248, 245)    # generated white dress, far from skin
    inpaint = np.zeros((32, 32), np.uint8)
    inpaint[8:16, 12:24] = 255
    inpaint[22:30, 8:24] = 255
    skin = np.zeros((32, 32), np.uint8)
    skin[8:16, 4:12] = 255

    out = harmonize_generated_region(orig, gen, inpaint, skin)
    check(int(out[12, 16, 0]) < 245, f"generated skin R did not drop toward original: {out[12, 16]}")
    check(int(out[12, 16, 1]) < 198, f"generated skin G stayed too pale: {out[12, 16]}")
    check(tuple(out[12, 6]) == (210, 165, 135), "original skin pixel must be untouched")
    check(tuple(out[26, 16]) == (250, 248, 245), "white dress must not be tinted as skin")


@test
def test_harmonize_accepts_work_sized_masks_on_full_res():
    import numpy as np
    from undress_core import harmonize_generated_region

    orig = np.full((64, 48, 3), 20, np.uint8)
    orig[8:24, 8:24] = (210, 165, 135)
    gen = np.full((16, 12, 3), 180, np.uint8)
    mask = np.zeros((16, 12), np.uint8)
    mask[:, 6:] = 255
    skin = np.zeros((16, 12), np.uint8)
    skin[2:6, 2:6] = 255
    out = harmonize_generated_region(orig, gen, mask, skin)
    check(out.shape == orig.shape, f"shape {out.shape}")
    check(tuple(out[10, 8]) == (210, 165, 135), "full-res keep pixel must stay original")



@test
def test_inpaint_condition_sets_masked_pixels_to_minus_one():
    import numpy as np
    from undress_core import make_inpaint_condition

    rgb = np.full((8, 8, 3), 200, np.uint8)
    mask = np.zeros((8, 8), np.uint8)
    mask[2:6, 2:6] = 255
    cond = make_inpaint_condition(rgb, mask)
    check(cond.shape == (1, 3, 8, 8), f"shape {cond.shape}")
    check(cond.dtype == np.float32, f"dtype {cond.dtype}")
    check(float(cond[0, 0, 0, 0]) == np.float32(200 / 255.0), "unmasked pixel should stay in 0-1")
    check(float(cond[0, 0, 4, 4]) == -1.0, "masked pixel must be -1 for inpaint ControlNet")



@test
def test_inpaint_mask_feathers_the_head_edge():
    import numpy as np
    from undress_core import build_inpaint_mask

    person = np.full((120, 120), 255, np.uint8)
    face = [40, 40, 80, 80]
    mask = build_inpaint_mask(person, face, feather_px=12)
    # A pixel just outside the expanded keep-core should be neither 0 nor 255.
    edge = mask[40 - 6, 60]
    check(0 < int(edge) < 255, f"head edge should be feathered, got {edge}")


@test
def test_annotate_face_preview_does_not_mutate_original():
    from PIL import Image
    from undress_core import annotate_face_preview

    original = Image.new("RGB", (80, 80), (10, 20, 30))
    annotated = annotate_face_preview(original, [20, 8, 60, 40])
    check(original.getpixel((10, 10)) == (10, 20, 30), "original pixel mutated")
    check(annotated is not original, "must return a copy")
    cx, cy = 40, 24
    orig_c = original.getpixel((cx, cy))
    new_c = annotated.getpixel((cx, cy))
    check(new_c != orig_c, "face keep overlay was not drawn")
    check(new_c[1] > new_c[0], "protected face should be tinted green")


@test
def test_protection_preview_tints_background_keep_and_torso_restyle():
    import numpy as np
    from PIL import Image
    from undress_core import annotate_face_preview, protection_preview_masks

    rgb = np.full((100, 80, 3), (40, 90, 190), np.uint8)
    rgb[8:42, 22:58] = (210, 168, 140)
    rgb[48:96, 24:56] = (20, 20, 20)
    rgb[50:90, 4:16] = (210, 168, 140)
    keep, restyle = protection_preview_masks(rgb, [22, 8, 58, 42])
    check(keep[12, 8] == 255, "backdrop must be protected")
    check(keep[24, 40] == 255, "face must be protected")
    check(keep[70, 10] == 255, "arm skin must be protected")
    check(restyle[70, 40] == 255, "torso dress must be restyle")
    check(keep[70, 40] == 0, "dress must not also be keep")
    preview = annotate_face_preview(Image.fromarray(rgb), [22, 8, 58, 42])
    px = preview.getpixel((8, 12))
    check(px[1] > px[0], "backdrop overlay should look green")
    dx = preview.getpixel((40, 70))
    check(dx[0] > dx[1], "dress overlay should look red")


@test
def test_terminate_process_actually_stops_the_child():
    import subprocess
    from undress_core import terminate_process

    proc = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(60)"],
    )
    terminate_process(proc, wait_seconds=5)
    check(proc.poll() is not None, "child still running after terminate_process")


@test
def test_undress_client_reads_marker_line_and_kills_on_timeout():
    import subprocess
    from undress_core import UndressClient, RESULT_MARKER

    worker = r"""
import sys, json, time
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")
for line in sys.stdin:
    line = line.strip()
    if not line or line == "EXIT":
        break
    job = json.loads(line)
    if job.get("sleep"):
        time.sleep(float(job["sleep"]))
    print("Fetching 18 files", flush=True)
    print("__UNDRESS_RESULT__" + json.dumps({"success": True, "echo": job.get("n")}), flush=True)
"""
    client = UndressClient(
        python_exe=sys.executable,
        script_args=["-c", worker],
        is_module_script=True,
    )
    try:
        got = client.generate({"n": 7}, timeout=10)
        check(got["echo"] == 7, f"echo mismatch: {got}")
        check(got["success"] is True, f"success lost: {got}")

        try:
            client.generate({"n": 1, "sleep": 30}, timeout=1)
        except TimeoutError:
            pass
        else:
            raise AssertionError("timeout should raise TimeoutError")
        check(client.proc is None or client.proc.poll() is not None,
              "timed-out worker must be dead")
    finally:
        client.close()

    # RESULT_MARKER is the contract the fake worker used
    check(RESULT_MARKER == "__UNDRESS_RESULT__", RESULT_MARKER)


@test
def test_parse_map_inpaints_clothes_keeps_hair_face_arms():
    import numpy as np
    from undress_core import inpaint_from_parse_map

    labels = np.zeros((80, 64), np.uint8)
    labels[8:20, 20:44] = 2     # hair
    labels[20:36, 22:42] = 11   # face
    labels[36:74, 18:46] = 7    # dress
    labels[40:70, 4:16] = 14    # left arm
    labels[40:70, 48:60] = 15   # right arm
    mask = inpaint_from_parse_map(labels, extra_keep=None, feather_px=1)
    check(mask[14, 32] < 40, f"hair must be keep, got {mask[14, 32]}")
    check(mask[28, 32] < 40, f"face must be keep, got {mask[28, 32]}")
    check(mask[55, 10] < 40, f"arm must be keep, got {mask[55, 10]}")
    check(mask[55, 32] > 180, f"dress must be inpaint, got {mask[55, 32]}")
    check(mask[2, 2] == 0, "background must stay keep")


@test
def test_grow_straps_catches_thin_dark_line_next_to_the_dress():
    import numpy as np
    from undress_core import grow_straps_into_garment

    h, w = 80, 60
    labels = np.zeros((h, w), np.uint8)
    labels[8:22, 18:42] = 2      # hair
    labels[20:36, 20:40] = 11    # face
    labels[48:76, 16:44] = 7     # dress
    labels[40:70, 2:12] = 14     # arm
    rgb = np.full((h, w, 3), (40, 90, 200), np.uint8)
    rgb[labels == 7] = (15, 15, 15)
    rgb[33:50, 17:20] = (18, 18, 18)  # spaghetti strap left of the face
    mask = grow_straps_into_garment(labels, rgb)
    check(mask[40, 18] == 255, f"strap must be inpaint, got {mask[40, 18]}")
    check(mask[28, 30] == 0, "face must stay keep")
    check(mask[55, 6] == 0, "arm must stay keep")
    check(mask[60, 30] == 255, "dress must stay inpaint")
    check(mask[45, 50] == 0, "colorful backdrop must not become strap")


@test
def test_garment_mask_inpaints_upper_ruffles_labeled_as_face():
    """SegFormer often labels neckline ruffles as face. The torso gap must still inpaint them."""
    import numpy as np
    from undress_core import garment_inpaint_mask

    h, w = 100, 80
    labels = np.zeros((h, w), np.uint8)
    labels[6:22, 22:58] = 2
    labels[18:52, 24:56] = 11
    labels[62:96, 22:58] = 7
    labels[50:95, 2:16] = 14
    rgb = np.full((h, w, 3), (40, 90, 200), np.uint8)
    rgb[labels == 7] = (20, 20, 20)
    rgb[40:62, 26:54] = (18, 18, 18)
    person = np.zeros((h, w), np.uint8)
    person[6:96, 18:60] = 255
    person[50:95, 2:16] = 255
    mask = garment_inpaint_mask(
        labels, rgb, face_bbox=[24, 18, 56, 40], person_mask=person
    )
    check(mask[50, 40] == 255, f"upper ruffles must be inpaint, got {mask[50, 40]}")
    check(mask[28, 40] == 0, "actual face must stay keep")
    check(mask[70, 8] == 0, "arm must stay keep")
    check(mask[80, 40] == 255, "lower dress must stay inpaint")
    check(mask[12, 40] == 0, "hair must stay keep")


@test
def test_garment_mask_keeps_skin_cleavage_in_the_torso():
    """Plunging necklines: inpaint the side garment, not the exposed chest."""
    import numpy as np
    from undress_core import garment_inpaint_mask

    h, w = 100, 80
    labels = np.zeros((h, w), np.uint8)
    labels[6:22, 22:58] = 2
    labels[18:40, 24:56] = 11
    labels[48:96, 16:28] = 7
    labels[48:96, 52:64] = 7
    labels[50:95, 2:14] = 14
    rgb = np.full((h, w, 3), (40, 90, 200), np.uint8)
    rgb[18:40, 24:56] = (210, 168, 140)
    rgb[42:96, 30:50] = (210, 168, 140)
    rgb[labels == 7] = (20, 20, 20)
    person = np.zeros((h, w), np.uint8)
    person[6:96, 16:64] = 255
    person[50:95, 2:14] = 255
    mask = garment_inpaint_mask(
        labels, rgb, face_bbox=[24, 18, 56, 40], person_mask=person
    )
    check(mask[70, 40] == 0, f"cleavage must stay keep, got {mask[70, 40]}")
    check(mask[70, 22] == 255, f"side dress must inpaint, got {mask[70, 22]}")
    check(mask[28, 40] == 0, "face must stay keep")


@test
def test_garment_mask_inpaints_getty_on_the_dress_not_the_backdrop():
    """Stock-photo bars on fabric must go; the same bar on the backdrop must stay."""
    import numpy as np
    from undress_core import garment_inpaint_mask

    h, w = 120, 80
    labels = np.zeros((h, w), np.uint8)
    labels[8:24, 22:58] = 2
    labels[18:40, 24:56] = 11
    labels[40:110, 22:58] = 7
    labels[50:105, 4:16] = 14
    rgb = np.full((h, w, 3), (40, 90, 200), np.uint8)
    rgb[labels == 7] = (20, 20, 20)
    rgb[52:68, :] = (160, 160, 162)
    person = np.zeros((h, w), np.uint8)
    person[8:110, 20:60] = 255
    person[50:105, 4:16] = 255
    mask = garment_inpaint_mask(
        labels, rgb, face_bbox=[24, 18, 56, 40], person_mask=person
    )
    check(mask[60, 40] == 255, f"Getty on the dress must inpaint, got {mask[60, 40]}")
    check(mask[60, 2] == 0, "Getty on the backdrop must stay keep")
    check(mask[28, 40] == 0, "face must stay keep")
    check(mask[80, 10] == 0, "arm must stay keep")


@test
def test_clean_binary_mask_fills_holes_and_drops_specks():
    import numpy as np
    from undress_core import clean_binary_mask

    m = np.zeros((80, 80), np.uint8)
    m[10:70, 10:70] = 255
    m[30:36, 30:36] = 0
    m[2:4, 2:4] = 255
    out = clean_binary_mask(m)
    check(out[33, 33] == 255, "hole inside the garment must be filled")
    check(out[3, 3] == 0, "tiny speck must be dropped")
    check(out[40, 40] == 255, "main garment must stay")


@test
def test_fill_masked_region_replaces_only_the_mask():
    import numpy as np
    from undress_core import fill_masked_region

    rgb = np.full((20, 20, 3), 10, np.uint8)
    mask = np.zeros((20, 20), np.uint8)
    mask[5:15, 5:15] = 255
    out = fill_masked_region(rgb, mask, (200, 160, 140))
    check(tuple(out[10, 10]) == (200, 160, 140), f"mask fill {out[10, 10]}")
    check(tuple(out[1, 1]) == (10, 10, 10), "outside mask must stay")


@test
def test_restyle_body_mask_covers_the_torso_not_the_old_dress_silhouette():
    import numpy as np
    from undress_core import restyle_body_mask

    h, w = 100, 80
    labels = np.zeros((h, w), np.uint8)
    labels[6:22, 22:58] = 2
    labels[18:40, 24:56] = 11
    labels[70:96, 24:56] = 7
    labels[48:96, 2:14] = 14
    person = np.zeros((h, w), np.uint8)
    person[6:96, 16:64] = 255
    person[48:96, 2:14] = 255
    mask = restyle_body_mask(
        labels, person_mask=person, face_bbox=[24, 18, 56, 40]
    )
    check(mask[55, 40] == 255, f"torso gap must be inpaint, got {mask[55, 40]}")
    check(mask[80, 40] == 255, "lower dress must be inpaint")
    check(mask[28, 40] == 0, "face must stay keep")
    check(mask[70, 8] == 0, "arm must stay keep")
    check(mask[10, 4] == 0, "background must stay keep")


@test
def test_mask_crop_box_pads_and_stays_inside_the_image():
    import numpy as np
    from undress_core import mask_crop_box

    m = np.zeros((100, 80), np.uint8)
    m[40:70, 30:50] = 255
    x0, y0, x1, y1 = mask_crop_box(m, pad_frac=0.2)
    check(x0 < 30 and y0 < 40, f"must pad outward, got {(x0, y0, x1, y1)}")
    check(x1 > 50 and y1 > 70, f"must pad outward, got {(x0, y0, x1, y1)}")
    check(x0 >= 0 and y0 >= 0 and x1 <= 80 and y1 <= 100, f"out of bounds {(x0, y0, x1, y1)}")


@test
def test_identity_keep_does_not_protect_face_bleed_on_the_chest():
    import numpy as np
    from undress_core import identity_keep_mask

    labels = np.zeros((80, 60), np.uint8)
    labels[10:50, 15:45] = 11
    labels[20:70, 2:12] = 14
    wm = np.zeros((80, 60), np.uint8)
    wm[40:50, :] = 255
    keep = identity_keep_mask(labels, face_bbox=[18, 12, 42, 32], watermark=wm)
    check(keep[20, 30] == 255, "real face must be keep")
    check(keep[45, 30] == 0, "face-bleed on the chest must not be keep")
    check(keep[40, 6] == 0, "watermark on the arm must not be keep")
    check(keep[60, 6] == 255, "arm away from watermark must stay keep")


@test
def test_watermark_banner_finds_gray_bar_on_black_fabric():
    import numpy as np
    from undress_core import watermark_banner_mask

    rgb = np.full((120, 80, 3), (18, 18, 18), np.uint8)
    rgb[52:68, 4:76] = (88, 88, 90)
    mask = watermark_banner_mask(rgb)
    check(mask[60, 40] == 255, f"dark Getty overlay must be inpaint, got {mask[60, 40]}")
    check(mask[10, 40] == 0, "black fabric away from the bar must not be watermark")


@test
def test_watermark_banner_mask_finds_gray_bar_not_the_backdrop():
    import numpy as np
    from undress_core import watermark_banner_mask

    rgb = np.full((120, 80, 3), (40, 90, 190), np.uint8)
    rgb[52:68, 4:76] = (160, 160, 162)
    mask = watermark_banner_mask(rgb)
    check(mask[60, 40] == 255, f"gray banner must be inpaint, got {mask[60, 40]}")
    check(mask[10, 40] == 0, "blue backdrop must not be watermark")


@test
def test_watermark_banner_stays_on_the_body_not_the_backdrop():
    import numpy as np
    from undress_core import watermark_banner_mask

    rgb = np.full((120, 80, 3), (40, 90, 190), np.uint8)
    rgb[52:68, :] = (160, 160, 162)
    person = np.zeros((120, 80), np.uint8)
    person[20:110, 20:60] = 255
    mask = watermark_banner_mask(rgb, person_mask=person)
    check(mask[60, 40] == 255, f"Getty on the body must inpaint, got {mask[60, 40]}")
    check(mask[60, 8] == 0, "Getty on the left backdrop must stay keep")
    check(mask[60, 70] == 0, "Getty on the right backdrop must stay keep")
    check((mask[60] > 127).mean() < 0.7, "watermark must not fill the whole row")


@test
def test_pose_control_scale_is_zero_on_waist_up_portraits():
    from undress_core import pose_control_scale

    check(pose_control_scale([100, 80, 400, 500], (768, 512)) == 0.0, "large face must disable pose")
    check(pose_control_scale([200, 40, 280, 120], (768, 512)) == 0.55, "small face can keep pose")
    check(pose_control_scale(None, (768, 512)) == 0.0, "no face must disable pose")


@test
def test_feather_mask_at_size_softens_after_upscale():
    import numpy as np
    from undress_core import feather_mask_at_size

    small = np.zeros((8, 8), np.uint8)
    small[2:6, 2:6] = 255
    big = feather_mask_at_size(small, (32, 32), feather_px=4)
    check(big.shape == (32, 32), f"shape {big.shape}")
    check(big[16, 16] > 200, "center must stay inpaint")
    edge = int(big[8, 16])
    check(0 < edge < 255, f"upscaled edge must be feathered, got {edge}")


@test
def test_watermark_on_arm_stays_inpaint_after_keep_punch():
    import numpy as np
    from undress_core import grow_straps_into_garment, harden_inpaint_mask, watermark_banner_mask

    h, w = 120, 80
    labels = np.zeros((h, w), np.uint8)
    labels[8:22, 22:58] = 2
    labels[20:40, 24:56] = 11
    labels[55:110, 22:58] = 7
    labels[50:110, 2:20] = 14
    rgb = np.full((h, w, 3), (40, 90, 190), np.uint8)
    rgb[labels == 7] = (20, 20, 20)
    rgb[58:74, 3:77] = (160, 160, 162)
    composite = np.maximum(grow_straps_into_garment(labels, rgb), watermark_banner_mask(rgb))
    parser_keep = (np.isin(labels, (1, 2, 3, 11, 16)).astype(np.uint8)) * 255
    arm_keep = (np.isin(labels, (14, 15)).astype(np.uint8)) * 255
    wm = watermark_banner_mask(rgb)
    arm_keep[wm > 127] = 0
    hard_keep = np.maximum(parser_keep, arm_keep)
    composite[hard_keep > 127] = 0
    model = harden_inpaint_mask(composite, hard_keep=hard_keep, dilate_px=9)
    check(model[66, 10] == 255, f"Getty bar on arm must inpaint, got {model[66, 10]}")
    check(model[90, 10] == 0, "arm skin away from watermark must stay keep")
    check(model[30, 40] == 0, "face must stay keep")
    check(model[80, 40] == 255, "dress must stay inpaint")


@test
def test_parse_map_punches_hands_out_of_the_dress():
    import numpy as np
    from undress_core import inpaint_from_parse_map

    labels = np.full((40, 40), 7, np.uint8)
    hands = np.zeros((40, 40), np.uint8)
    hands[28:38, 4:14] = 255
    mask = inpaint_from_parse_map(labels, extra_keep=hands, feather_px=1)
    check(mask[32, 8] == 0, f"hand on dress must stay keep, got {mask[32, 8]}")
    check(mask[10, 20] > 180, "dress away from hand must inpaint")


@test
def test_paste_work_onto_original_keeps_native_face_pixels():
    import numpy as np
    from undress_core import paste_work_onto_original

    orig = np.full((32, 32, 3), 11, np.uint8)
    work = np.full((8, 8, 3), 200, np.uint8)
    mask = np.zeros((8, 8), np.uint8)
    mask[:, 4:] = 255
    out = paste_work_onto_original(orig, work, mask)
    check(out.shape == (32, 32, 3), f"shape {out.shape}")
    check(tuple(out[8, 4]) == (11, 11, 11), f"keep side mutated: {out[8, 4]}")
    check(int(out[8, 28, 0]) > 150, f"inpaint side not taken from work: {out[8, 28]}")


@test
def test_ensure_local_model_uses_cached_inpaint_snapshot():
    from pathlib import Path
    from undress_core import INPAINT_MODEL_ID, ensure_local_model

    src = ensure_local_model(INPAINT_MODEL_ID, "model_index.json")
    root = Path(src)
    check(root.is_dir(), f"expected a folder, got {src}")
    check((root / "model_index.json").is_file(), "model_index.json missing")
    check((root / "unet").exists(), "unet folder missing")


@test
def test_write_undress_output_persists_png():
    import tempfile
    from undress_core import write_undress_output

    png_header = (
        b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
        b"\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00"
        b"\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = write_undress_output("abc123", png_header, tmp)
        check(Path(path).exists(), f"missing {path}")
        check(Path(path).read_bytes()[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG")
        check(Path(path).name == "abc123.png", Path(path).name)


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        known = ", ".join(t.__name__ for t in _TESTS)
        print(f"No test matches '{pattern}'.\nKnown: {known}")
        return 1

    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()

    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
