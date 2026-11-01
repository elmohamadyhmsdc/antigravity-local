"""
Phase 6 PC half (roadmap 7.4): tattoo patch matching with OpenCV, and POST /v1/analyze/marks. CPU only, no models.

    venv\\Scripts\\python.exe test_mobile_marks.py
"""

import sys
import traceback

import cv2
import numpy as np

import mark_matching as mm

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def skin(size=(260, 220), seed=0):
    rng = np.random.default_rng(seed)
    base = np.full((size[0], size[1], 3), (120, 160, 215), np.uint8)
    return cv2.add(base, rng.integers(0, 12, base.shape, dtype=np.uint8))


def tattoo(seed=1):
    """A distinctive drawing: a dragon-ish mess of strokes, a ring and some lettering."""
    img = skin()
    rng = np.random.default_rng(seed)
    pts = rng.integers(30, 190, (14, 2))
    for a, b in zip(pts[:-1], pts[1:]):
        cv2.line(img, tuple(int(v) for v in a), tuple(int(v) for v in b), (35, 35, 40), 3)
    cx, cy = (int(v) for v in rng.integers(70, 150, 2))
    cv2.circle(img, (cx, cy), int(rng.integers(25, 50)), (30, 30, 35), 3)
    word = ["LOVE", "MOM", "FAITH", "RAGE", "ZEN"][seed % 5]
    cv2.putText(img, word, (int(rng.integers(20, 80)), int(rng.integers(190, 230))), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (40, 30, 30), 3)
    cv2.putText(img, f"K{seed}", (int(rng.integers(100, 150)), int(rng.integers(40, 80))), cv2.FONT_HERSHEY_DUPLEX, 1.0, (30, 30, 60), 2)
    return img


def warp(img, angle=12, scale=0.9, shift=(8, -6)):
    h, w = img.shape[:2]
    m = cv2.getRotationMatrix2D((w / 2, h / 2), angle, scale)
    m[:, 2] += shift
    return cv2.warpAffine(img, m, (w, h), borderMode=cv2.BORDER_REFLECT)


@test
def test_the_same_tattoo_matches_even_rotated_scaled_and_noisy():
    ref = tattoo()
    noisy = np.clip(warp(ref).astype(np.int16) + np.random.default_rng(3).integers(-8, 8, ref.shape), 0, 255).astype(np.uint8)
    result = mm.match_patches(ref, [noisy])[0]
    check(result["inliers"] >= 15 and result["inlier_ratio"] >= 0.4 and result["mirrored"] is False, result)


@test
def test_a_mirror_selfie_matches_flipped():
    ref = tattoo()
    result = mm.match_patches(ref, [cv2.flip(ref, 1)])[0]
    check(result["mirrored"] is True and result["inliers"] >= 20, result)


@test
def test_other_ink_and_plain_skin_do_not_match():
    ref = tattoo(1)
    results = mm.match_patches(ref, [tattoo(2), skin(seed=5), tattoo(1)])
    other, plain, same = results
    check(other["inliers"] < 12, other)
    check(plain["inliers"] == 0, plain)
    check(same["inliers"] > 3 * max(other["inliers"], 1), (same, other))


@test
def test_empty_or_tiny_candidates_are_zero_not_errors():
    ref = tattoo()
    results = mm.match_patches(ref, [None, np.zeros((0, 0, 3), np.uint8), np.full((8, 8, 3), 128, np.uint8)])
    check([r["inliers"] for r in results] == [0, 0, 0], results)
    check(all("mirrored" in r for r in results), results)


@test
def test_prepare_caps_the_size_and_decode_rejects_junk():
    big = np.zeros((2000, 1000, 3), np.uint8)
    check(max(mm.prepare(big).shape) <= mm.MAX_SIDE, "downscaled")
    check(mm.decode_patch(b"not an image") is None, "junk")
    ok, buf = cv2.imencode(".jpg", tattoo())
    check(mm.decode_patch(buf.tobytes()).shape[:2] == (260, 220), "jpeg")


def jpeg(img):
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


@test
def test_api_returns_one_result_per_candidate_and_validates():
    import test_mobile_api_contract as c
    with c.Env() as e:
        ref = tattoo()
        files = [("reference", ("ref.jpg", jpeg(ref), "image/jpeg")),
                 ("candidates", ("a.jpg", jpeg(warp(ref)), "image/jpeg")),
                 ("candidates", ("b.jpg", jpeg(tattoo(2)), "image/jpeg"))]
        r = e.client.post("/v1/analyze/marks", files=files, headers=e.auth)
        check(r.status_code == 200, f"{r.status_code} {r.text}")
        body = r.json()
        c.check_schema("AnalyzeMarksResponse", body)
        check([x["index"] for x in body["results"]] == [0, 1], body)
        check(body["results"][0]["inliers"] > body["results"][1]["inliers"], body)
        c.check_schema("AnalyzeMarksResponse", c.fixture("AnalyzeMarksResponse.two_candidates"))

        bad_ref = [("reference", ("r.jpg", b"junk", "image/jpeg")), ("candidates", ("a.jpg", jpeg(ref), "image/jpeg"))]
        r = e.client.post("/v1/analyze/marks", files=bad_ref, headers=e.auth)
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_image", r.text)

        too_many = [("reference", ("r.jpg", jpeg(ref), "image/jpeg"))] + [("candidates", (f"{i}.jpg", jpeg(ref), "image/jpeg")) for i in range(65)]
        r = e.client.post("/v1/analyze/marks", files=too_many, headers=e.auth)
        check(r.status_code == 400 and r.json()["error"]["code"] == "bad_request", r.text)

        only_ref = [("reference", ("r.jpg", jpeg(ref), "image/jpeg"))]
        check(e.client.post("/v1/analyze/marks", files=only_ref, headers=e.auth).status_code == 400, "no candidates")
        check(e.client.post("/v1/analyze/marks", files=files, headers={"Authorization": "Bearer nope"}).status_code == 401, "token")
        junk_candidate = [("reference", ("r.jpg", jpeg(ref), "image/jpeg")), ("candidates", ("a.jpg", b"junk", "image/jpeg"))]
        r = e.client.post("/v1/analyze/marks", files=junk_candidate, headers=e.auth)
        check(r.status_code == 200 and r.json()["results"][0]["inliers"] == 0, "an undecodable candidate is just no match")


def main(argv):
    failed = 0
    for fn in _TESTS:
        try:
            fn()
            print(f"PASS  {fn.__name__}")
        except Exception:  # noqa: BLE001
            failed += 1
            print(f"FAIL  {fn.__name__}")
            traceback.print_exc()
    print(f"\n{len(_TESTS) - failed}/{len(_TESTS)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
