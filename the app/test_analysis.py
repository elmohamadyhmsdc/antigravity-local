"""
analysis.analyze_frame - the pure frame-analysis core shared by the gallery scanner and the
mobile API. CPU only, no models: faces and bodies are scripted fakes.

    venv\\Scripts\\python.exe test_analysis.py
"""

import sys
import traceback

import numpy as np

_TESTS = []


def test(fn):
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def _img(w=640, h=480):
    return np.random.default_rng(0).integers(0, 255, (h, w, 3), dtype=np.uint8)


@test
def test_analyze_frame_returns_faces_quality_gate_bodies_and_pairs():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeBody, FakeFace, unit
    import face_quality

    good = FakeFace((60, 50, 200, 230), unit(1))
    weak = FakeFace((400, 60, 424, 90), unit(2), det_score=0.4)  # fails the detector gate
    body = FakeBody((20, 30, 260, 460), (130, 90))

    class Bodies:
        available = True

        def analyze(self, img, score_thr=0.5):
            return [body]

    img = _img()
    result = analyze_frame(None, Bodies(), img, AnalyzeOptions(),
                           detect=lambda im: [good, weak],
                           assess=lambda im, f: face_quality.assess(f, None))
    check(result.passes_gate == [True, False], f"gate: {result.passes_gate}")
    check(len(result.quality) == 2 and result.quality[0]["quality_version"] == face_quality.QUALITY_VERSION,
          "quality v2 must be attached to every face")
    check(result.pairs and result.pairs[0][0] == 0 and result.pairs[0][1] == 0, f"pairs: {result.pairs}")
    check(result.body_of_face == {0: 0} and result.face_of_body == {0: 0}, "pair lookups")
    check(len(result.appearances) == 1 and result.appearances[0] is not None and len(result.appearances[0]) == 80,
          "each body needs its 80-float outfit descriptor")
    check((result.image_w, result.image_h) == (640, 480), "image size")
    check({"detect", "quality", "body"} <= set(result.timings_ms), f"timings: {result.timings_ms}")


@test
def test_analyze_frame_skips_bodies_when_off_or_unavailable():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeFace, unit
    import face_quality

    called = []

    class Bodies:
        available = True

        def analyze(self, img, score_thr=0.5):
            called.append(score_thr)
            return []

    class Broken:
        available = False

        def analyze(self, img, score_thr=0.5):
            raise AssertionError("must not be called when unavailable")

    face = FakeFace((60, 50, 200, 230), unit(1))
    kw = dict(detect=lambda im: [face], assess=lambda im, f: face_quality.assess(f, None))
    analyze_frame(None, Bodies(), _img(), AnalyzeOptions(detect_bodies=False), **kw)
    check(not called, "detect_bodies=False must not run the body model")
    r = analyze_frame(None, Broken(), _img(), AnalyzeOptions(), **kw)
    check(r.bodies == [] and r.pairs == [], "an unavailable body model means no bodies, not a crash")
    r = analyze_frame(None, None, _img(), AnalyzeOptions(), **kw)
    check(r.bodies == [], "no body analyzer at all")
    analyze_frame(None, Bodies(), _img(), AnalyzeOptions(body_score=0.7), **kw)
    check(called == [0.7], f"body_score must reach the detector: {called}")


@test
def test_quality_gate_follows_the_requested_minimum():
    from analysis import AnalyzeOptions, analyze_frame
    from mobile_api.testing import FakeFace, unit
    import face_quality

    face = FakeFace((60, 50, 200, 230), unit(1))
    kw = dict(detect=lambda im: [face], assess=lambda im, f: face_quality.assess(f, None))
    lenient = analyze_frame(None, None, _img(), AnalyzeOptions(min_face_quality=0.1), **kw)
    strict = analyze_frame(None, None, _img(), AnalyzeOptions(min_face_quality=0.99), **kw)
    check(lenient.passes_gate == [True] and strict.passes_gate == [False], "min_face_quality is the gate")


@test
def test_crops_pad_and_clamp_like_the_scanner_does():
    from analysis import body_crop, face_crop
    from mobile_api.testing import FakeBody, FakeFace, unit

    img = _img(640, 480)
    face = FakeFace((100, 100, 200, 200), unit(1))
    c = face_crop(img, face)  # 100px box + 20 % pad each side
    check(c.shape[:2] == (140, 140), f"face crop with 20% pad: {c.shape}")
    edge = FakeFace((0, 0, 50, 50), unit(1))
    check(face_crop(img, edge).shape[:2] == (60, 60), "crop is clamped at the image border (50px + 10px pad on one side)")
    tall = FakeBody((10, 0, 110, 470), (60, 20))
    check(body_crop(img, tall.bbox, max_height=100).shape[0] <= 100, "body crops are capped in height")


@test
def test_library_scanner_still_routes_through_analysis():
    """LibraryScanner keeps detect_faces/assess_face as instance-overridable hooks (test_gallery stubs them)."""
    import analysis
    import library_scanner

    check(library_scanner.LibraryScanner.det_sizes(_img(800, 600)) == analysis.det_sizes(_img(800, 600)),
          "det_sizes must be the shared implementation")
    check(library_scanner._FileState._face_crop is analysis.face_crop, "face crops must be shared")
    check(library_scanner._FileState._body_crop is analysis.body_crop, "body crops must be shared")


def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()
    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
